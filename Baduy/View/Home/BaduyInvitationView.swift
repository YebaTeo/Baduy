import SwiftUI
import RealityKit
import ARKit
import AVFoundation

/// Room 1 is virtual; only room 2 requests and uses the device camera.
struct BaduyInvitationView: View {
    let locationVerified: Bool
    @State private var scene = InvitationScene()
    @State private var showingCamera = false
    @State private var entryCharacter = BaduyCharacter.cowo
    @State private var requestingCamera = false
    @State private var cameraMessage: String?
    @State private var yaw: Float = 0
    @State private var zoom: Float = 2.4
    @GestureState private var drag: CGFloat = 0
    @GestureState private var magnification: CGFloat = 1
    @State private var dragStartYaw: Float?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if showingCamera {
                cameraRoom
            } else {
                virtualRoom
            }
        }
        .overlay(alignment: .top) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(showingCamera ? "Ruang 2 · Kamera AR" : "Ruang 1 · Dunia virtual",
                          systemImage: showingCamera ? "viewfinder" : "map.fill")
                        .font(.caption.bold())
                    Text(locationVerified ? "Di luar Ciboleger" : "Lokasi belum terverifikasi")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12).background(.regularMaterial, in: Capsule())
                Spacer()
                if showingCamera {
                    Button { showingCamera = false } label: {
                        Image(systemName: "arrow.left").padding(14)
                            .background(.regularMaterial, in: Circle())
                    }.accessibilityLabel("Kembali ke dunia virtual")
                }
            }.padding()
        }
        .alert("Kamera AR", isPresented: Binding(
            get: { cameraMessage != nil },
            set: { if !$0 { cameraMessage = nil } }
        )) {
            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                Button("Buka Pengaturan") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button("Tutup", role: .cancel) { cameraMessage = nil }
        } message: { Text(cameraMessage ?? "") }
        .onChange(of: scenePhase) { _, phase in
            // Recreate camera tracking after returning from another app.
            if phase == .background { showingCamera = false }
            #if DEBUG
            if phase != .active { scene.movement = .zero }
            #endif
        }
    }

    private var virtualRoom: some View {
        RealityView { content in
            content.camera = .virtual
            content.cameraTarget = scene.cameraEntity
            content.add(scene.root)
            scene.updateCamera(yaw: yaw, distance: zoom)
            #if DEBUG
            scene.subscription?.cancel()
            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                scene.move(deltaTime: Float(event.deltaTime))
            }
            #endif
        } update: { _ in
            scene.updateCamera(yaw: yaw + Float(drag) * 0.008,
                               distance: zoomDistance(magnification))
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            if let character = scene.character(for: value.entity), scene.canOpen(character) {
                enterCameraRoom(character)
            }
        })
        .simultaneousGesture(DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragStartYaw == nil { dragStartYaw = yaw }
                yaw = (dragStartYaw ?? yaw) + Float(value.translation.width) * 0.008
                scene.updateCamera(yaw: yaw, distance: zoomDistance(magnification))
            }
            .onEnded { _ in dragStartYaw = nil })
        .simultaneousGesture(MagnifyGesture()
            .updating($magnification) { value, state, _ in state = value.magnification }
            .onChanged { value in
                scene.updateCamera(yaw: yaw, distance: zoomDistance(value.magnification))
            }
            .onEnded { zoom = zoomDistance($0.magnification) })
        .ignoresSafeArea()
        .task {
            await scene.loadCharacters()
            scene.updateCamera(yaw: yaw, distance: zoom)
        }
        .onDisappear {
            #if DEBUG
            scene.movement = .zero
            scene.subscription?.cancel()
            scene.subscription = nil
            #endif
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                #if DEBUG
                HStack {
                    DebugMovementStick { scene.movement = $0 }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Analog · Debug").font(.caption.bold())
                        Text("Geser analog untuk berjalan. Geser layar untuk melihat sekeliling.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                #endif
                Capsule().fill(.secondary.opacity(0.3)).frame(width: 36, height: 4)
                Text("Pilih teman ceritamu").font(.headline)
                if scene.loadingCharacters { ProgressView("Memuat cowo dan cewe…") }
                if let error = scene.characterError { Text(error).font(.caption).foregroundStyle(.red) }
                Text(scene.canOpen ? "Ketuk karakter terdekat untuk bertemu di AR." : "Cowo: tentang Baduy. Cewe: frasa Sunda. Dekati salah satunya.")
                    .font(.subheadline).multilineTextAlignment(.center)
                HStack {
                    Label("\(scene.distance.formatted(.number.precision(.fractionLength(1)))) m virtual",
                          systemImage: "figure.walk")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    ForEach(BaduyCharacter.allCases) { character in
                        Button {
                            if scene.canOpen(character) { enterCameraRoom(character) }
                            else { scene.approach(character) }
                        } label: {
                            Text((scene.canOpen(character) ? "Buka: " : "Dekati: ") + character.title)
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(character == .cowo ? .cyan : .purple)
                        .disabled(requestingCamera)
                    }
                }
            }
            .padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
            .padding()
        }
    }

    private var cameraRoom: some View {
        ARCharactersView(initialCharacter: entryCharacter)
    }

    private func zoomDistance(_ scale: CGFloat) -> Float {
        min(3, max(1.2, zoom / Float(max(0.1, scale))))
    }

    private func enterCameraRoom(_ character: BaduyCharacter) {
        guard scene.canOpen(character), !requestingCamera else { return }
        entryCharacter = character
        guard ARWorldTrackingConfiguration.isSupported else {
            cameraMessage = "Ruang kamera AR memerlukan iPhone atau iPad yang mendukung ARKit. Dunia virtual tetap bisa digunakan."
            return
        }
        requestingCamera = true
        Task { @MainActor in
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            requestingCamera = false
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                cameraMessage = "Izinkan kamera di Pengaturan untuk membuka ruang kedua."
                return
            }
            showingCamera = true
        }
    }
}

#if DEBUG
private struct DebugMovementStick: View {
    var onMove: (SIMD2<Float>) -> Void
    @GestureState private var offset = CGSize.zero
    private let radius: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(.cyan.opacity(0.1))
            Circle().stroke(.cyan.opacity(0.35), lineWidth: 1)
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .foregroundStyle(.cyan.opacity(0.35))
            Circle().fill(.cyan).frame(width: 38, height: 38)
                .offset(offset)
        }
        .frame(width: 112, height: 112)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .updating($offset) { value, state, _ in
                let length = hypot(value.translation.width, value.translation.height)
                let scale = length > radius ? radius / length : 1
                state = CGSize(width: value.translation.width * scale,
                               height: value.translation.height * scale)
            })
        // GestureState also resets on cancellation, so movement never stays latched.
        .onChange(of: offset) { _, value in
            onMove(SIMD2(Float(value.width / radius), Float(-value.height / radius)))
        }
        .onDisappear { onMove(.zero) }
        .accessibilityLabel("Analog gerakan debug")
        .accessibilityHint("Geser ke arah tujuan untuk menggerakkan pemain virtual")
    }
}
#endif

/// An illustrative local world; movement here never changes the user's real GPS fix.
@MainActor
@Observable
private final class InvitationScene {
    let root = Entity()
    private var invitations: [BaduyCharacter: Entity] = [:]
    private(set) var loadingCharacters = true
    private(set) var characterError: String?
    private let camera = PerspectiveCamera()
    var cameraEntity: Entity { camera }
    private let player = Entity()
    private(set) var playerPosition = SIMD3<Float>(0, 0, 3)
    private func destination(for character: BaduyCharacter) -> SIMD3<Float> {
        SIMD3(character == .cowo ? -1.4 : 1.4, 0, -1)
    }
    var nearestCharacter: BaduyCharacter {
        BaduyCharacter.allCases.min { distance(to: $0) < distance(to: $1) } ?? .cowo
    }
    private func distance(to character: BaduyCharacter) -> Float {
        simd_distance(playerPosition, destination(for: character))
    }
    func canOpen(_ character: BaduyCharacter) -> Bool { invitations[character] != nil && distance(to: character) <= 1.2 }
    func character(for entity: Entity) -> BaduyCharacter? {
        var current: Entity? = entity
        while let candidate = current {
            if let match = invitations.first(where: { $0.value === candidate }) { return match.key }
            current = candidate.parent
        }
        return nil
    }
    @ObservationIgnored private var cameraYaw: Float = 0
    @ObservationIgnored private var cameraDistance: Float = 2.4
    #if DEBUG
    @ObservationIgnored var movement = SIMD2<Float>.zero
    @ObservationIgnored var subscription: EventSubscription?
    #endif
    var distance: Float { distance(to: nearestCharacter) }
    var canOpen: Bool { canOpen(nearestCharacter) }

    init() {
        root.addChild(camera)
        camera.position = [0, 1.6, 4.2]
        // Closed 10 x 10 x 4 metre room; camera and player stay inside its shell.
        for (size, position, color): (SIMD3<Float>, SIMD3<Float>, UIColor) in [
            ([10.4, 0.2, 10.4], [0, -0.1, 0], .white),
            ([10.4, 0.2, 10.4], [0, 4.1, 0], .init(white: 0.94, alpha: 1)),
            ([0.2, 4, 10.4], [-5.1, 2, 0], .init(white: 0.75, alpha: 1)),
            ([0.2, 4, 10.4], [5.1, 2, 0], .init(white: 0.82, alpha: 1)),
            ([10, 4, 0.2], [0, 2, -5.1], .init(white: 0.87, alpha: 1)),
            ([10, 4, 0.2], [0, 2, 5.1], .init(white: 0.8, alpha: 1))
        ] {
            let surface = ModelEntity(mesh: .generateBox(size: size),
                                      materials: [UnlitMaterial(color: color)])
            surface.position = position
            root.addChild(surface)
        }
        let light = DirectionalLight()
        light.light.intensity = 2_500
        light.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
        root.addChild(light)
        // A cyan directional player marker, built from two short bars.
        for side: Float in [-1, 1] {
            let wing = ModelEntity(mesh: .generateBox(size: [0.18, 0.12, 0.55], cornerRadius: 0.04),
                                  materials: [UnlitMaterial(color: .cyan)])
            wing.position = [side * 0.13, 0.1, 0]
            wing.orientation = simd_quatf(angle: -side * .pi / 5, axis: [0, 1, 0])
            player.addChild(wing)
        }
        player.position = playerPosition
        root.addChild(player)
        camera.look(at: [0, 0.7, -0.5], from: [0, 1.6, 4.2], relativeTo: nil)
    }

    func loadCharacters() async {
        print("[Baduy][Map] loadCharacters start")
        defer { loadingCharacters = false }
        for character in BaduyCharacter.allCases {
            do {
                let model = try await character.makeEntity(height: 1.5)
                try Task.checkCancellation()
                model.position = destination(for: character)
                invitations[character] = model
                root.addChild(model)
                print("[Baduy][Map] ADDED \(character.rawValue) position=\(model.position)")
            } catch is CancellationError {
                print("[Baduy][Map] CANCELLED \(character.rawValue)")
                return
            } catch {
                characterError = "Gagal memuat \(character.rawValue).usdz: \(error.localizedDescription)"
                print("[Baduy][Map] ERROR \(character.rawValue): \(error)")
            }
        }
        print("[Baduy][Map] loadCharacters complete count=\(invitations.count)")
    }

    func approach(_ character: BaduyCharacter) {
        guard distance(to: character) > 1 else { return }
        setPlayerPosition(playerPosition + simd_normalize(destination(for: character) - playerPosition)
                          * min(0.6, distance(to: character) - 1))
    }

    #if DEBUG
    func move(deltaTime: Float) {
        guard simd_length(movement) > 0.08 else { return }
        let forward = SIMD3<Float>(-sin(cameraYaw), 0, -cos(cameraYaw))
        let right = SIMD3<Float>(cos(cameraYaw), 0, -sin(cameraYaw))
        let velocity = right * movement.x + forward * movement.y
        // Frame-rate independent, proportional stick speed; cap resume-time jumps.
        setPlayerPosition(playerPosition + velocity * 2 * min(max(deltaTime, 0), 0.05))
    }
    #endif

    private func setPlayerPosition(_ position: SIMD3<Float>) {
        playerPosition = SIMD3(min(4.6, max(-4.6, position.x)), 0,
                               min(4.6, max(-4.6, position.z)))
        player.position = playerPosition
        updateCamera(yaw: cameraYaw, distance: cameraDistance)
    }

    func updateCamera(yaw: Float, distance: Float) {
        cameraYaw = yaw
        cameraDistance = distance
        // Frame the player and both interaction points. Looking only at the player
        // leaves the imported characters behind the virtual camera's useful view.
        let focus = (destination(for: .cowo) + destination(for: .cewe)) * 0.5
        let target = playerPosition * 0.35 + focus * 0.65 + SIMD3<Float>(0, 0.7, 0)
        var eye = target + SIMD3<Float>(sin(yaw) * distance * 0.7,
                                        distance * 0.65, cos(yaw) * distance * 0.7)
        eye.x = min(4.8, max(-4.8, eye.x))
        eye.z = min(4.8, max(-4.8, eye.z))
        eye.y = min(3.7, eye.y)
        camera.look(at: target, from: eye, relativeTo: nil)
    }
}
