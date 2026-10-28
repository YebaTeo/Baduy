import ARKit
import Combine
import RealityKit
import UIKit

/// A procedural experience, not a prescribed account of customary farming practice.
@MainActor
final class NgahumaScene: NSObject, ObservableObject {
    enum Stage: Int { case entering, clearing, prepared, burning, planting, complete }
    @Published private(set) var stage: Stage = .entering
    @Published private(set) var count = 0
    @Published private(set) var progress: Double = 0
    @Published private(set) var tracking = "Menyiapkan lingkungan 360°. Gerakkan perangkat perlahan."
    @Published var muted = false { didSet { audio?.gain = muted ? -80 : -8 } }
    private weak var view: ARView?
    private var anchor: AnchorEntity?
    private var subscription: Cancellable?
    private var patches: [Entity] = []
    private var plants: [Entity] = []
    private var soils: [ModelEntity] = []
    private var emitters: [Entity] = []
    private var completed = Set<Int>()
    @Published private(set) var assetError: String?
    @Published private(set) var loadingAssets = true
    private var materials: NgahumaMaterials?
    private var windTime: Float = 0
    private var wildGrass: [Entity] = []
    private var fireLight: PointLight?
    private var fireSoundSource: Entity?
    private var charred = Set<Int>()
    private var elapsed: Double = 0
    private var preview = false
    private var audio: AudioPlaybackController?
    private var sound: AudioFileResource?
    private var particleTexture: TextureResource?
    private var trackingPaused = false
    private var tap: UITapGestureRecognizer?
    private var pan: UIPanGestureRecognizer?
    private var previewCamera: PerspectiveCamera?
    private var yaw: Float = 0
    private var pitch: Float = -0.25
    private let feedback = UIImpactFeedbackGenerator(style: .medium)

    var title: String {
        switch stage {
        case .entering: "Masuki lingkungan"
        case .clearing: "Siapkan lahan"
        case .prepared: "Lahan siap"
        case .burning: "Amati perubahan"
        case .planting: "Tanam kehidupan baru"
        case .complete: "Lahan kembali tumbuh"
        }
    }
    var instruction: String {
        switch stage {
        case .entering: "Lingkungan terbuka otomatis di sekeliling Anda setelah pelacakan siap."
        case .clearing: "Menoleh ke sekeliling dan ketuk rumpun untuk merapikan vegetasi. \(count)/9"
        case .prepared: "Mulai adegan pembakaran virtual dan amati perubahan lahan."
        case .burning: "Api, bara, dan asap bergerak di atas lahan virtual."
        case .planting: "Cari petak abu di sekeliling Anda dan ketuk untuk menumbuhkan tunas. \(count)/9"
        case .complete: "Anda telah menyelesaikan rangkaian simulasi ngahuma."
        }
    }

    func attach(_ view: ARView, preview: Bool) {
        self.view = view
        self.preview = preview
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let image = renderer.image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
            }
        }
        if let cgImage = image.cgImage {
            particleTexture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color))
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        view.addGestureRecognizer(tap)
        self.tap = tap
        if preview {
            view.environment.background = .color(UIColor(red: 0.09, green: 0.14, blue: 0.13, alpha: 1))
            let camera = PerspectiveCamera()
            camera.position = [0, 1.5, 0]
            previewCamera = camera
            updatePreviewCamera()
            let pan = UIPanGestureRecognizer(target: self, action: #selector(lookAround(_:)))
            view.addGestureRecognizer(pan)
            self.pan = pan
            let cameraAnchor = AnchorEntity(world: .zero)
            cameraAnchor.addChild(camera)
            view.scene.addAnchor(cameraAnchor)
            if materials != nil { build(at: matrix_identity_float4x4) }
        } else {
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = []
            configuration.environmentTexturing = .automatic
            view.session.run(configuration)
        }
        subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated { self?.update(event.deltaTime) }
        }
    }

    func prepareAssets() async {
        guard materials == nil else { return }
        loadingAssets = true
        assetError = nil
        defer { loadingAssets = false }
        do {
            let loaded = try await NgahumaMaterials.load()
            try Task.checkCancellation()
            materials = loaded
            if preview, anchor == nil { build(at: matrix_identity_float4x4) }
        } catch is CancellationError {
            return
        } catch {
            assetError = "Tekstur belum dapat dimuat. Ketuk coba lagi."
        }
    }

    func loadAudio() async {
        guard let url = Bundle.main.url(forResource: "ngahuma-fire", withExtension: "wav") else { return }
        sound = try? await AudioFileResource(contentsOf: url, configuration: .init(shouldLoop: true))
        guard !Task.isCancelled else { sound = nil; return }
        if stage == .burning { startAudio() }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let view else { return }
        let location = gesture.location(in: view)
        guard stage == .clearing || stage == .planting else { return }
        var entity = view.entity(at: location)
        while let current = entity {
            if current.name.hasPrefix("patch-"), let index = Int(current.name.dropFirst(6)) {
                interact(index)
                return
            }
            entity = current.parent
        }
    }

    private func interact(_ index: Int) {
        guard completed.insert(index).inserted else { return }
        feedback.impactOccurred(intensity: 0.65)
        if stage == .clearing {
            plants[index].scale = [1, 0.12, 1]
            plants[index].orientation = simd_quatf(angle: 0.2, axis: [0, 1, 0])
        } else {
            plants[index].isEnabled = true
            plants[index].scale = [0.45, 0.45, 0.45]
            if let materials {
                for clump in plants[index].children {
                    for card in clump.children {
                        (card as? ModelEntity)?.model?.materials = [materials.foliage(young: true)]
                    }
                }
            }
        }
        count = completed.count
        if count == 9 { stage = stage == .clearing ? .prepared : .complete }
    }

    private func build(at transform: simd_float4x4) {
        guard let view, let materials else { return }
        let root = AnchorEntity(world: transform)
        buildSurroundings(in: root)
        for index in 0..<9 {
            let patch = Entity()
            patch.name = "patch-\(index)"
            let angle = Float(index) / 9 * 2 * .pi
            patch.position = [sin(angle) * 2.4, 0, -cos(angle) * 2.4]
            patch.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            let soil = ModelEntity(mesh: .generatePlane(width: 1.15, depth: 1.15), materials: [materials.earth()])
            soil.position.y = 0.015
            soil.generateCollisionShapes(recursive: false)
            patch.addChild(soil)
            let vegetation = Entity()
            for stalk in 0..<5 {
                let height = Float(0.65 + Double((stalk * 7 + index) % 8) * 0.055)
                let clump = materials.clump(height: height)
                clump.position = [Float(stalk % 3) * 0.28 - 0.28, 0, Float(stalk / 3) * 0.35 - 0.18]
                clump.orientation = simd_quatf(angle: Float(stalk + index) * 1.3, axis: [0, 1, 0])
                vegetation.addChild(clump)
            }
            // One generous hit volume per plot also catches taps on the standing plants.
            patch.components.set(CollisionComponent(shapes: [.generateBox(size: [0.9, 1.3, 0.9])]))
            patch.addChild(vegetation)
            root.addChild(patch)
            patches.append(patch)
            plants.append(vegetation)
            soils.append(soil)
            for kind in 0..<3 {
                let emitter = Entity()
                emitter.position.y = kind == 1 ? 0.35 : 0.08
                emitter.components.set(particles(kind: kind))
                emitter.isEnabled = false
                patch.addChild(emitter)
                emitters.append(emitter)
            }
        }
        view.scene.addAnchor(root)
        anchor = root
        stage = .clearing
        tracking = ""
    }

    @objc private func lookAround(_ gesture: UIPanGestureRecognizer) {
        guard let view else { return }
        let movement = gesture.translation(in: view)
        yaw -= Float(movement.x) * 0.005
        pitch = min(0.9, max(-1.2, pitch + Float(movement.y) * 0.005))
        gesture.setTranslation(.zero, in: view)
        updatePreviewCamera()
    }

    private func updatePreviewCamera() {
        previewCamera?.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    private func buildSurroundings(in root: Entity) {
        guard let materials else { return }
        var skyMaterial = UnlitMaterial(color: .white)
        skyMaterial.color = .init(tint: .white, texture: .init(materials.panorama))
        skyMaterial.faceCulling = .front
        let sky = ModelEntity(mesh: .generateSphere(radius: 65), materials: [skyMaterial])
        sky.position.y = 1.5
        root.addChild(sky)
        if let terrain = try? materials.terrain() { root.addChild(terrain) }
        let sun = DirectionalLight()
        sun.light.intensity = 1400
        sun.light.color = UIColor(red: 1, green: 0.94, blue: 0.83, alpha: 1)
        sun.shadow = .init()
        sun.look(at: .zero, from: [8, 12, 4], relativeTo: nil)
        root.addChild(sun)
        // A shared material and crossed cards replace the former box stalks / sphere trees.
        for index in 0..<110 {
            let angle = Float(index) * 2.399963
            let radius = 4.2 + Float(index % 19) * 0.43
            let clump = materials.clump(height: 0.5 + Float(index % 7) * 0.12)
            clump.position = [sin(angle) * radius, -0.09, cos(angle) * radius]
            clump.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
            root.addChild(clump)
            wildGrass.append(clump)
        }
        let light = PointLight()
        light.light.color = .orange
        light.light.intensity = 0
        light.light.attenuationRadius = 5
        light.position = [0, 0.6, -2.4]
        root.addChild(light)
        fireLight = light
        let source = Entity()
        source.position = [0, 0.4, -2.4]
        root.addChild(source)
        fireSoundSource = source
    }

    private func particles(kind: Int) -> ParticleEmitterComponent {
        var component = ParticleEmitterComponent()
        component.emitterShape = .box
        component.emitterShapeSize = [0.65, 0.02, 0.65]
        component.birthDirection = .local
        component.emissionDirection = [0, 1, 0]
        component.speed = kind == 2 ? 0.9 : 0.45
        component.speedVariation = 0.2
        component.mainEmitter.image = kind == 0 ? materials?.flame : particleTexture
        component.mainEmitter.birthRate = kind == 0 ? 24 : 12
        component.mainEmitter.lifeSpan = kind == 1 ? 2.4 : 0.9
        component.mainEmitter.size = kind == 0 ? 0.46 : (kind == 1 ? 0.22 : 0.018)
        component.mainEmitter.sizeVariation = 0.04
        component.mainEmitter.sizeMultiplierAtEndOfLifespan = kind == 1 ? 3 : 0.1
        component.mainEmitter.opacityCurve = .quickFadeInOut
        component.mainEmitter.blendMode = kind == 1 ? .alpha : .additive
        component.mainEmitter.color = .evolving(start: .single(kind == 1 ? UIColor.gray.withAlphaComponent(0.35) : .yellow), end: .single(kind == 1 ? UIColor.lightGray.withAlphaComponent(0) : .red))
        if kind == 0 {
            component.mainEmitter.color = .constant(.single(.white))
            component.mainEmitter.billboardMode = .billboardYAligned
        }
        component.mainEmitter.acceleration = [0.08, 0.15, 0]
        component.mainEmitter.noiseStrength = 0.15
        component.mainEmitter.spreadingAngle = 0.25
        return component
    }

    func ignite() {
        guard stage == .prepared else { return }
        elapsed = 0
        stage = .burning
        startAudio()
        feedback.impactOccurred()
    }

    private func startAudio() {
        guard let sound, let fireSoundSource, audio == nil else { return }
        audio = fireSoundSource.playAudio(sound)
        audio?.gain = muted ? -80 : -8
    }

    private func update(_ delta: Double) {
        if !preview, let state = view?.session.currentFrame?.camera.trackingState {
            guard case .normal = state else {
                tracking = "Pelacakan terbatas. Arahkan kamera kembali ke lahan atau mulai ulang."
                audio?.pause()
                setTrackingPaused(true)
                return
            }
            if stage == .entering, materials != nil, let camera = view?.session.currentFrame?.camera {
                // Capture the origin once; never parent the world to the moving camera.
                // Ground height is an authored eye-height offset, not a detected floor.
                var origin = matrix_identity_float4x4
                origin.columns.3 = camera.transform.columns.3
                origin.columns.3.y -= 1.5
                build(at: origin)
            }
            setTrackingPaused(false)
            if stage != .entering { tracking = "" }
        }
        windTime += Float(min(delta, 0.1))
        for (index, clump) in wildGrass.enumerated() {
            clump.orientation = simd_quatf(angle: Float(index) * 2.399963, axis: [0, 1, 0])
                * simd_quatf(angle: sin(windTime * 1.3 + Float(index)) * 0.035, axis: [0, 0, 1])
        }
        guard stage == .burning else { return }
        fireLight?.light.intensity = 350 + 100 * sin(windTime * 13)
        if audio?.isPlaying == false { audio?.play() }
        elapsed += min(delta, 0.1)
        progress = min(elapsed / 18, 1)
        let activePatch = min(8, Int(elapsed / 0.85))
        fireSoundSource?.position = patches[activePatch].position + [0, 0.4, 0]
        fireLight?.position = patches[activePatch].position + [0, 0.6, 0]
        if elapsed > 14 { fireLight?.light.intensity *= Float(max(0, (17 - elapsed) / 3)) }
        for index in 0..<9 {
            let localTime = elapsed - Double(index) * 0.85
            for kind in 0..<3 {
                emitters[index * 3 + kind].isEnabled = localTime > 0 && localTime < (kind == 1 ? 10 : 7)
            }
            if localTime > 0 && localTime < 3, let materials {
                var scorched = materials.earth()
                let shade = CGFloat(1 - min(localTime / 3, 1) * 0.7)
                scorched.baseColor.tint = UIColor(white: shade, alpha: 1)
                soils[index].model?.materials = [scorched]
                plants[index].scale.y = max(0.015, 0.12 * Float(1 - localTime / 3))
            }
            if localTime > 3, charred.insert(index).inserted {
                plants[index].isEnabled = false
                soils[index].model?.materials = materials.map { [$0.earth(burned: true)] } ?? []
            }
        }
        if elapsed >= 18 { finishBurn() }
    }

    private func setTrackingPaused(_ paused: Bool) {
        guard trackingPaused != paused else { return }
        trackingPaused = paused
        for entity in emitters {
            guard var component = entity.components[ParticleEmitterComponent.self] else { continue }
            component.simulationState = paused ? .pause : .play
            entity.components.set(component)
        }
    }

    func finishBurn() {
        guard stage == .burning else { return }
        fireLight?.light.intensity = 0
        emitters.forEach { $0.isEnabled = false }
        plants.forEach { $0.isEnabled = false }
        soils.forEach { $0.model?.materials = materials.map { [$0.earth(burned: true)] } ?? [] }
        audio?.stop()
        audio = nil
        completed.removeAll()
        count = 0
        progress = 1
        stage = .planting
    }

    func reset() {
        audio?.stop()
        audio = nil
        anchor?.removeFromParent()
        anchor = nil
        wildGrass.removeAll()
        fireLight = nil
        fireSoundSource = nil
        charred.removeAll()
        patches.removeAll(); plants.removeAll(); soils.removeAll(); emitters.removeAll()
        completed.removeAll()
        count = 0; progress = 0; elapsed = 0
        trackingPaused = false
        stage = .entering
        tracking = "Menyiapkan lingkungan 360°. Gerakkan perangkat perlahan."
        if preview { build(at: matrix_identity_float4x4) }
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
        audio?.stop()
        audio = nil
        if let pan { view?.removeGestureRecognizer(pan) }
        pan = nil
        previewCamera = nil
        if let tap { view?.removeGestureRecognizer(tap) }
        tap = nil
        view?.session.pause()
    }
}
