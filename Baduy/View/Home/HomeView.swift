import SwiftUI
import RealityKit

struct HomeView: View {
    @State private var model: HomeViewModel
    @State private var scene = MapScene()
    @State private var yaw: Float = 0
    @State private var distance: Float = 180
    @GestureState private var drag: CGFloat = 0
    @GestureState private var magnification: CGFloat = 1
    @State private var dragStartYaw: Float?
    @Environment(\.scenePhase) private var scenePhase

    // USDZ must use metres and the same geographic/vertical origin as the model.
    // Supply its surveyed rotation, scale, and offset using terrainTransform.
    private let terrainName: String?
    private let terrainTransform: Transform

    init(model: HomeViewModel? = nil, terrainName: String? = nil,
         terrainTransform: Transform = .identity) {
        _model = State(initialValue: model ?? HomeViewModel(landmarks: MapLandmark.baduyPoints))
        self.terrainName = terrainName
        self.terrainTransform = terrainTransform
    }

    var body: some View {
        Group {
            if model.isAtCiboleger == true {
                mapView
                    .onDisappear { scene = MapScene() }
            } else {
                BaduyInvitationView(locationVerified: model.isAtCiboleger != nil)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start() } else { model.stop() }
        }
    }

    private var mapView: some View {
        RealityView { content in
            content.camera = .virtual
            content.cameraTarget = scene.cameraEntity
            content.add(scene.root)
            scene.update(model: model, yaw: yaw, distance: distance)
            // Keep the camera and drag gestures live while USDZ files decode.
            Task { @MainActor in
                await scene.loadAssets(model: model, terrainName: terrainName,
                                       terrainTransform: terrainTransform)
                scene.update(model: model, yaw: yaw, distance: distance)
            }
        } update: { _ in
            scene.update(model: model, yaw: yaw + Float(drag) * 0.008,
                         distance: zoomDistance(magnification))
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            var entity: Entity? = value.entity
            while let current = entity {
                if let landmark = model.landmarks.first(where: { $0.id == current.name }) {
                    model.selectedLandmark = landmark
                    break
                }
                entity = current.parent
            }
        })
        .simultaneousGesture(DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragStartYaw == nil { dragStartYaw = yaw }
                yaw = (dragStartYaw ?? yaw) + Float(value.translation.width) * 0.008
                scene.update(model: model, yaw: yaw, distance: zoomDistance(magnification))
            }
            .onEnded { _ in dragStartYaw = nil })
        .simultaneousGesture(MagnifyGesture()
            .updating($magnification) { value, state, _ in state = value.magnification }
            .onChanged { value in
                scene.update(model: model, yaw: yaw, distance: zoomDistance(value.magnification))
            }
            .onEnded { distance = zoomDistance($0.magnification) })
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Baduy Map").font(.headline)
                Text(model.status).font(.caption)
                if let error = scene.assetError { Text(error).font(.caption) }
            }
            .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Points of interest").font(.headline)
                    Spacer()
                    Button {
                        model.selectedLandmark = nil
                    } label: {
                        Label("My location", systemImage: "location.fill")
                    }
                    .disabled(model.playerPosition == nil)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(model.landmarks) { landmark in
                            Button {
                                model.selectedLandmark = landmark
                            } label: {
                                Label(landmark.name, systemImage: "mappin.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(model.selectedLandmark?.id == landmark.id ? .blue : .primary)
                            .accessibilityAddTraits(model.selectedLandmark?.id == landmark.id ? .isSelected : [])
                        }
                    }
                }
                if let landmark = model.selectedLandmark {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(landmark.name).font(.headline)
                            Text(landmark.detail).font(.subheadline)
                            Text("Arrival radius: \(Int(landmark.radius)) m").font(.caption)
                            if let metres = model.distance(to: landmark) {
                                Text(metres < 1_000
                                     ? "\(Int(metres)) m away"
                                     : "\((metres / 1_000).formatted(.number.precision(.fractionLength(1)))) km away")
                                    .font(.caption)
                            }
                            if let source = landmark.sourceURL, let url = URL(string: source) {
                                Link("Location reference", destination: url).font(.caption)
                            }
                        }
                        Spacer()
                        Button("Close") { model.selectedLandmark = nil }
                    }
                }
            }
            .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
        .alert(item: $model.enteredLandmark) { landmark in
            Alert(title: Text(landmark.name), message: Text("You entered this landmark’s radius."),
                  dismissButton: .default(Text("OK")))
        }
    }

    private func zoomDistance(_ magnification: CGFloat) -> Float {
        min(600, max(30, distance / Float(max(0.1, magnification))))
    }
}

@MainActor
@Observable
private final class MapScene {
    let root = Entity()
    private let camera = PerspectiveCamera()
    var cameraEntity: Entity { camera }
    private let player = ModelEntity(mesh: .generateSphere(radius: 3),
                                     materials: [UnlitMaterial(color: .systemBlue)])
    private let ground = ModelEntity(mesh: .generatePlane(width: 2_000, depth: 2_000),
                                     materials: [UnlitMaterial(color: .init(red: 0.5, green: 0.68, blue: 0.4, alpha: 1))])
    private let mapContent = Entity()
    private var landmarkEntities: [String: Entity] = [:]
    private var characterEntities: [BaduyCharacter: Entity] = [:]
    private var didPlaceMap = false
    private var assetsLoaded = false
    private(set) var assetError: String?

    init() {
        camera.camera.far = 20_000
        root.addChild(camera)
        root.addChild(ground)
        root.addChild(mapContent)
        root.addChild(player)
        player.isEnabled = false
        let light = DirectionalLight()
        light.light.intensity = 3_000
        light.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
        root.addChild(light)
    }

    func loadAssets(model: HomeViewModel, terrainName: String?, terrainTransform: Transform) async {
        if let terrainName {
            do {
                let terrain = try await Entity(named: terrainName)
                terrain.transform = terrainTransform
                root.addChild(terrain)
                ground.isEnabled = false
            } catch {
                assetError = "Could not load terrain: \(terrainName)"
            }
        }
        for landmark in model.landmarks {
            let entity: Entity
            if let name = landmark.modelName {
                do { entity = try await Entity(named: name) }
                catch {
                    assetError = "Could not load landmark: \(name)"
                    entity = marker()
                }
            } else {
                entity = marker()
            }
            entity.name = landmark.id
            entity.generateCollisionShapes(recursive: true)
            entity.components.set(InputTargetComponent())
            landmarkEntities[landmark.id] = entity
            mapContent.addChild(entity)
        }
        // The two map characters are code-built so the map is visible even
        // without waiting for the optional USDZ assets.
        for character in BaduyCharacter.allCases {
            let entity: Entity
            do {
                // Use the same normalized USDZ asset as the camera AR room.
                entity = try await character.makeEntity(height: 1.5)
            } catch {
                assetError = "Gagal memuat \(character.rawValue).usdz: \(error.localizedDescription)"
                continue
            }
            entity.name = "map-\(character.rawValue)"
            characterEntities[character] = entity
            mapContent.addChild(entity)
        }
        assetsLoaded = true
    }

    func update(model: HomeViewModel, yaw: Float, distance: Float) {
        if assetsLoaded, !didPlaceMap, let origin = model.origin {
            for landmark in model.landmarks {
                landmarkEntities[landmark.id]?.position = origin.position(
                    for: landmark.coordinate, elevation: landmark.elevation)
            }
            let characterCoordinates: [BaduyCharacter: CLLocationCoordinate2D] = [
                .cowo: .init(latitude: -6.5948, longitude: 106.2259),
                .cewe: .init(latitude: -6.5953, longitude: 106.2262)
            ]
            for (character, coordinate) in characterCoordinates {
                characterEntities[character]?.position = origin.position(for: coordinate, elevation: 0)
            }
            for trail in model.trails {
                for (start, end) in zip(trail, trail.dropFirst()) {
                    let a = origin.position(for: start, elevation: 0.15)
                    let b = origin.position(for: end, elevation: 0.15)
                    let length = simd_distance(a, b)
                    guard length > 0.01 else { continue }
                    let segment = ModelEntity(mesh: .generateBox(size: [2, 0.2, length]),
                                              materials: [UnlitMaterial(color: .systemYellow)])
                    segment.position = (a + b) / 2
                    segment.orientation = simd_quatf(from: [0, 0, 1], to: simd_normalize(b - a))
                    mapContent.addChild(segment)
                }
            }
            didPlaceMap = true
        }
        let selectedPosition = model.selectedLandmark.flatMap { landmark in
            model.origin?.position(for: landmark.coordinate, elevation: landmark.elevation)
        }
        let target = selectedPosition ?? model.playerPosition ?? .zero
        for (id, entity) in landmarkEntities {
            if let head = entity.findEntity(named: "poi-head") as? ModelEntity {
                head.model?.materials = [UnlitMaterial(color: model.selectedLandmark?.id == id
                                                       ? .systemYellow : .systemOrange)]
            }
        }
        player.isEnabled = model.playerPosition != nil
        player.position = (model.playerPosition ?? .zero) + SIMD3(0, 3, 0)
        // Keep the placeholder ground underneath the current camera focus.
        ground.position = target
        camera.look(at: target, from: target + SIMD3(sin(yaw) * distance,
                    distance * 0.9, cos(yaw) * distance), relativeTo: nil)
    }

    private func marker() -> Entity {
        let pin = Entity()
        let stem = ModelEntity(mesh: .generateCylinder(height: 10, radius: 0.8),
                               materials: [UnlitMaterial(color: .white)])
        stem.position.y = 5
        let head = ModelEntity(mesh: .generateSphere(radius: 4),
                               materials: [UnlitMaterial(color: .systemOrange)])
        head.name = "poi-head"
        head.position.y = 12
        pin.addChild(stem)
        pin.addChild(head)
        return pin
    }
}
