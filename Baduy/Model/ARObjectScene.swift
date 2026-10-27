import ARKit
import AVFoundation
import CoreHaptics
import Combine
import RealityKit
import UIKit

/// Owns one camera session and one model at a time.
@MainActor
final class ARObjectScene: NSObject, ObservableObject, UIGestureRecognizerDelegate {
    @Published private(set) var loading = false
    @Published private(set) var placed = false
    @Published private(set) var ready = false
    @Published private(set) var error: String?
    @Published private(set) var guidance = "Model tampil langsung. Geser untuk memutar, cubit untuk mengubah ukuran."

    private weak var view: ARView?
    private weak var inputView: UIView?
    @Published private(set) var interactionStatus = "Kontrol AR siap"
    private var anchor: AnchorEntity?
    private var cameraUpdates: Cancellable?
    private var object: ModelEntity?
    private var gestures: [UIGestureRecognizer] = []
    private var loadID = UUID()
    private var tapGesture: UITapGestureRecognizer?
    private var hapticPlayer: CHHapticPatternPlayer?
    private var hapticEngine: CHHapticEngine?
    private var loomStates: [Entity] = []
    private var loomRaised = false
    private var initialOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var lastTap = Date.distantPast
    private let weavingImpact = UIImpactFeedbackGenerator(style: .rigid)

    func attach(to view: ARView, inputView: UIView) {
        self.view = view
        self.inputView = inputView
        inputView.isMultipleTouchEnabled = true
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = []
        configuration.environmentTexturing = .automatic
        configuration.frameSemantics = []
        // Inspection models must remain visible over nearby furniture/people.
        view.environment.sceneUnderstanding.options.remove(.occlusion)
        view.renderOptions.insert(.disablePersonOcclusion)
        view.session.run(configuration)
        let tap = UITapGestureRecognizer(target: self, action: #selector(place(_:)))
        inputView.addGestureRecognizer(tap)
        tapGesture = tap
        cameraUpdates?.cancel()
        cameraUpdates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let frame = self.view?.session.currentFrame else { return }
                self.anchor?.transform = self.displayCameraTransform(frame.camera)
            }
        }
        // Loading and UIView creation are independent asynchronous lifecycles.
        if ready { showModel() }
    }

    func load(_ selection: BaduyARObject) async {
        let request = UUID()
        loadID = request
        removeObject()
        loading = true
        error = nil
        defer { if loadID == request { loading = false } }
        do {
            guard let url = Bundle.main.url(forResource: selection.resourceName, withExtension: "usdz") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let importedScene = try await Entity(contentsOf: url)
            let imported = Self.geometryOnly(importedScene)
            var variants: [Entity] = []
            var authoredView: simd_quatf?
            if selection == .tenun {
                for name in ["tenun turun", "tenun naik"] {
                    guard let variantURL = Bundle.main.url(forResource: name, withExtension: "usdz") else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let poseScene = try await Entity(contentsOf: variantURL)
                    if authoredView == nil {
                        authoredView = Self.authoredCameraOrientation(in: poseScene)?.inverse
                    }
                    variants.append(Self.geometryOnly(poseScene, repairLoomThreads: true))
                }
            }
            try Task.checkCancellation()
            guard loadID == request else { return }
            let normalized = Entity()
            let models = variants.isEmpty ? [imported] : variants
            // Measure the actual displayed poses together, in their parent's space.
            for model in models { normalized.addChild(model) }
            let bounds = normalized.visualBounds(relativeTo: normalized)
            let span = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
            guard span.isFinite, span > 0.0001 else { throw CocoaError(.fileReadCorruptFile) }
            let factor: Float = 0.28 / span
            normalized.scale = SIMD3(repeating: factor)
            normalized.position = -bounds.center * factor
            if !variants.isEmpty {
                loomStates = variants
                loomRaised = false
                weavingImpact.prepare()
            }
            let root = ModelEntity()
            root.addChild(normalized)
            let size = bounds.extents * factor
            root.collision = CollisionComponent(shapes: [
                .generateBox(size: SIMD3(max(size.x, 0.02), max(size.y, 0.02), max(size.z, 0.02)))
            ])
            let verified = root.visualBounds(relativeTo: root)
            let verifiedSpan = max(verified.extents.x, max(verified.extents.y, verified.extents.z))
            guard verifiedSpan.isFinite, abs(verifiedSpan - 0.28) < 0.01 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if variants.count == 2 { variants[1].isEnabled = false }
            // Express the geometry in the exported camera's view coordinates.
            // This includes RealityKit's USD Z-up to Y-up conversion and avoids
            // guessing a yaw in a different coordinate system.
            initialOrientation = authoredView ?? simd_quatf(angle: 0, axis: [0, 1, 0])
            object = root
            ready = true
            showModel()
            guidance = "Model tampil langsung. Geser untuk memutar, cubit untuk mengubah ukuran."
        } catch is CancellationError {
            // Changing objects or leaving the room cancels the old load.
        } catch {
            guard loadID == request else { return }
            self.error = "Model \(selection.title) belum dapat dimuat. Coba lagi."
            print("[Baduy][AR] \(selection.resourceName): \(error)")
        }
    }

    private static func authoredCameraOrientation(in entity: Entity) -> simd_quatf? {
        if entity.components[PerspectiveCameraComponent.self] != nil {
            return entity.orientation(relativeTo: nil)
        }
        for child in entity.children {
            if let orientation = authoredCameraOrientation(in: child) { return orientation }
        }
        return nil
    }

    /// USD exports include Blender cameras/lights. Never insert the imported
    /// scene directly: copy only meshes/materials and their local transforms.
    /// Fresh entities also exclude authored anchors, physics and animations.
    private static func geometryOnly(_ source: Entity, repairLoomThreads: Bool = false) -> Entity {
        let result = Entity()
        result.name = source.name
        result.transform = source.transform
        if var mesh = source.components[ModelComponent.self] {
            // These narrow thread meshes have no material binding in both USD poses.
            let unboundThreads: Set<String> = ["Plane_012", "Plane_013", "Plane_014", "Plane_016", "Plane_017", "Plane_018", "Plane_020", "Plane_021", "Plane_022"]
            if repairLoomThreads && unboundThreads.contains(source.name) {
                var thread = PhysicallyBasedMaterial()
                thread.baseColor = .init(tint: .white)
                thread.roughness = .init(floatLiteral: 0.8)
                thread.faceCulling = .none
                mesh.materials = Array(repeating: thread, count: max(1, mesh.materials.count))
            }
            result.components.set(mesh)
        }
        for child in source.children {
            let geometry = geometryOnly(child, repairLoomThreads: repairLoomThreads)
            if geometry.components[ModelComponent.self] != nil || !geometry.children.isEmpty {
                result.addChild(geometry)
            }
        }
        return result
    }

    @objc private func place(_ gesture: UITapGestureRecognizer) {
        guard ready, let view, let object else { return }
        let point = gesture.location(in: view)
        if placed {
            guard !loomStates.isEmpty, Date().timeIntervalSince(lastTap) > 0.18,
                  let hit = view.entity(at: point) else { return }
            var candidate: Entity? = hit
            while let entity = candidate, entity !== object { candidate = entity.parent }
            guard candidate === object else { return }
            weave()
            return
        }
    }

    /// ARCamera.transform uses sensor axes, not the portrait interface axes.
    /// Invert the orientation-aware view matrix to obtain screen-to-world axes.
    private func displayCameraTransform(_ camera: ARCamera) -> Transform {
        let orientation = view?.window?.windowScene?.interfaceOrientation ?? .portrait
        let resolved: UIInterfaceOrientation = orientation == .unknown ? .portrait : orientation
        return Transform(matrix: simd_inverse(camera.viewMatrix(for: resolved)))
    }

    private func showModel() {
        guard let view, let object else { return }
        removeGestures()
        anchor?.removeFromParent()
        // Explicit world anchor follows the live camera pose; no AR anchor
        // detection/resolution is required before RealityKit renders the model.
        let anchor = AnchorEntity(world: .zero)
        if let frame = view.session.currentFrame {
            anchor.transform = displayCameraTransform(frame.camera)
        }
        object.transform = .identity
        object.position = [0, 0.06, -0.8]
        object.orientation = initialOrientation
        anchor.addChild(object)
        view.scene.addAnchor(anchor)
        self.anchor = anchor
        guard let inputView else { return }
        gestures = []
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.maximumNumberOfTouches = 2
        inputView.addGestureRecognizer(pan)
        tapGesture?.require(toFail: pan)
        gestures.append(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        pinch.delegate = self
        pan.delegate = self
        inputView.addGestureRecognizer(pinch)
        tapGesture?.require(toFail: pinch)
        gestures.append(pinch)
        placed = true
        if !loomStates.isEmpty {
            guidance = "Ketuk alat tenun untuk menenun. Geser untuk memutar, cubit untuk mengubah ukuran."
            return
        }
        guidance = "Geser satu jari untuk memutar, dua jari untuk memindahkan, cubit untuk mengubah ukuran."
    }

    func weave() {
        guard placed, loomStates.count == 2 else { return }
        lastTap = Date()
        loomRaised.toggle()
        loomStates[0].isEnabled = !loomRaised
        loomStates[1].isEnabled = loomRaised
        playWeavingHaptic()
        weavingImpact.prepare()
        guidance = loomRaised ? "Benang terangkat. Ketuk lagi untuk merapatkan tenunan." : "Tenunan dirapatkan. Ketuk lagi untuk mengangkat benang."
    }

    // Gestures work anywhere on the exposed camera, even if the model is
    // oversized or the user's fingers start outside its collision bounds.
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let view, let object, placed else { return }
        let delta = gesture.translation(in: view)
        gesture.setTranslation(.zero, in: view)
        guard gesture.state == .changed else { return }
        if gesture.numberOfTouches == 2 {
            let factor: Float = 0.6 / Float(max(view.bounds.width, 1))
            object.position.x = min(0.2, max(-0.2, object.position.x + Float(delta.x) * factor))
            object.position.y = min(0.25, max(-0.15, object.position.y - Float(delta.y) * factor))
            interactionStatus = "Posisi diperbarui"
            return
        }
        let yaw = simd_quatf(angle: Float(delta.x) * 0.008, axis: [0, 1, 0])
        let pitch = simd_quatf(angle: Float(delta.y) * 0.008, axis: [1, 0, 0])
        object.orientation = simd_normalize(yaw * pitch * object.orientation)
        interactionStatus = "Rotasi diterima"
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        guard let object, placed else { return }
        guard gesture.state == .changed else { return }
        let scale = min(1.5, max(0.4, object.scale.x * Float(gesture.scale)))
        object.scale = SIMD3(repeating: scale)
        gesture.scale = 1
        interactionStatus = "Ukuran: \(Int(scale * 100))%"
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        !(gestureRecognizer is UITapGestureRecognizer) && !(otherGestureRecognizer is UITapGestureRecognizer)
    }

    func playWeavingHaptic() {
        // Failure to configure audio must not skip haptic playback.
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
        do {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
                interactionStatus = "Perangkat tidak mendukung Core Haptics"
                weavingImpact.impactOccurred(intensity: 1)
                return
            }
            if hapticEngine == nil {
                let engine = try CHHapticEngine()
                engine.playsHapticsOnly = true
                hapticEngine = engine
            }
            guard let hapticEngine else { return }
            try hapticEngine.start()
            let events = [0.0, 0.09].map { time in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: loomRaised ? 0.7 : 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: loomRaised ? 0.4 : 0.8)
                ], relativeTime: time)
            }
            hapticPlayer = try hapticEngine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try hapticPlayer?.start(atTime: CHHapticTimeImmediate)
            interactionStatus = "Pola getaran diputar"
        } catch {
            interactionStatus = "Haptics: \(error.localizedDescription)"
            print("[Baduy][Haptics] \(error)")
            hapticEngine = nil
            weavingImpact.impactOccurred(intensity: 1)
        }
    }

    func reposition() {
        showModel()
    }

    func stop() {
        loadID = UUID()
        loading = false
        removeObject()
        hapticPlayer = nil
        hapticEngine?.stop(completionHandler: nil)
        hapticEngine = nil
        cameraUpdates?.cancel()
        cameraUpdates = nil
        view?.session.pause()
    }

    private func removeGestures() {
        for gesture in gestures { inputView?.removeGestureRecognizer(gesture) }
        gestures.removeAll()
    }

    private func removeObject() {
        removeGestures()
        object?.removeFromParent()
        anchor?.removeFromParent()
        anchor = nil
        placed = false
        loomStates.removeAll()
        loomRaised = false
        object = nil
        ready = false
    }
}
