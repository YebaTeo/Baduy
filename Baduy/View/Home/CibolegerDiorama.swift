import SwiftUI
import MapKit
import RealityKit

struct CibolegerDiorama: View {
    @ObservedObject var model: BaduyHomeViewModel
    let position: MapCameraPosition
    let onLandmark: (MapLandmark) -> Void
    let onCharacter: (BaduyCharacter) -> Void
    @ViewState private var scene = DioramaScene()
    @ViewState private var zoom: Float = 1
    @ViewState private var orbitAngle: Float = 0.35
    @ViewState private var orbitElevation: Float = 0.85
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.cameraTarget = scene.camera
            content.add(scene.root)
            scene.build(model)
            scene.update(model, region: position.region, zoom: zoom, angle: orbitAngle + Float(dragOffset.width) * 0.008, elevation: orbitElevation + Float(-dragOffset.height) * 0.005)
        } update: { _ in
            scene.update(model, region: position.region, zoom: zoom / Float(pinch), angle: orbitAngle + Float(dragOffset.width) * 0.008, elevation: orbitElevation + Float(-dragOffset.height) * 0.005)
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            var entity: Entity? = value.entity
            while let current = entity {
                if let landmark = model.landmarks.first(where: { $0.id == current.name }) { onLandmark(landmark); return }
                if let character = BaduyCharacter.allCases.first(where: { $0.rawValue == current.name }) { onCharacter(character); return }
                entity = current.parent
            }
        })
        .simultaneousGesture(DragGesture().updating($dragOffset) { value, state, _ in state = value.translation }
            .onEnded { value in
                orbitAngle += Float(value.translation.width) * 0.008
                orbitElevation = min(1.35, max(0.35, orbitElevation - Float(value.translation.height) * 0.005))
            })
        .simultaneousGesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { zoom = min(4, max(0.1, zoom / Float($0.magnification))) })
        .background(Color(red: 0.05, green: 0.10, blue: 0.19))
    }
}

@MainActor
private final class DioramaScene {
    let root = Entity()
    let camera = PerspectiveCamera()
    private let origin = MapLandmark.baduyPoints[0].coordinate
    private let ground = ModelEntity(mesh: .generatePlane(width: 20_000, depth: 20_000), materials: [UnlitMaterial(color: UIColor(red: 0.12, green: 0.23, blue: 0.38, alpha: 1))])
    private let player = BaduyLeafMarker.make()
    private var characters: [BaduyCharacter: Entity] = [:]
    private let terrain = CibolegerTerrain()
    // Convert MapKit coordinates to local metres, with north along negative Z.
    private func point(_ coordinate: CLLocationCoordinate2D) -> SIMD3<Float> {
        terrain.point(coordinate)
    }
    func build(_ model: BaduyHomeViewModel) {
        camera.camera.far = 40_000
        root.addChild(camera); root.addChild(ground); root.addChild(player)
        if terrain.available {
            do { root.addChild(try terrain.entity()) }
            catch { print("Terrain mesh failed: \(error)") }
        }
        let sunlight = DirectionalLight()
        sunlight.light.intensity = 2600
        sunlight.look(at: .zero, from: [1000,2000,800], relativeTo: nil)
        root.addChild(sunlight)
        for landmark in model.landmarks {
            let house = Entity()
            house.name = landmark.id
            house.position = point(landmark.coordinate)
            box(house, [16, 8, 12], [0, 8, 0], UIColor(red: 0.10, green: 0.24, blue: 0.30, alpha: 1))
            for sign: Float in [-1, 1] {
                let roof = box(house, [9, 1, 15], [sign * 3.8, 14, 0], UIColor(red: 0.88, green: 0.82, blue: 0.67, alpha: 1))
                roof.orientation = simd_quatf(angle: sign * -.pi / 5, axis: [0, 0, 1])
            }
            house.generateCollisionShapes(recursive: true)
            house.components.set(InputTargetComponent())
            root.addChild(house)
            // Small textile inlays on the illustrative landmark, not geographic features.
            for i in -2...2 {
                let diamond = box(house, [0.7, 0.7, 0.12], [Float(i) * 2, 7, 5.1], UIColor(red:0.77,green:0.74,blue:0.63,alpha:1))
                diamond.orientation = simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
            }
            for i in 0..<5 {
                let tree = ModelEntity(mesh: .generateCone(height: 9, radius: 3.5), materials: [UnlitMaterial(color: UIColor(red: 0.08, green: 0.25, blue: 0.25, alpha: 1))])
                let angle = Float(i) * 1.25
                tree.position = house.position + [cos(angle) * 25, 4.5, sin(angle) * 25]
                root.addChild(tree)
            }
        }
        addVillagePaths(model.landmarks)
        for character in BaduyCharacter.allCases {
            let entity = BaduyLeafMarker.makeCharacter()
            entity.name = character.rawValue
            entity.generateCollisionShapes(recursive: true)
            entity.components.set(InputTargetComponent())
            root.addChild(entity); characters[character] = entity
        }
    }
    private func addVillagePaths(_ landmarks: [MapLandmark]) {
        guard landmarks.count > 1 else { return }
        for pair in zip(landmarks, landmarks.dropFirst()) {
            let a = point(pair.0.coordinate) + [0, 1.2, 0]
            let b = point(pair.1.coordinate) + [0, 1.2, 0]
            let delta = b - a
            let path = ModelEntity(mesh: .generateBox(size: [3, 0.18, max(3, simd_length(delta))]), materials: [UnlitMaterial(color: UIColor(red: 0.72, green: 0.66, blue: 0.51, alpha: 1))])
            path.position = (a + b) / 2
            path.orientation = simd_quatf(from: [0, 0, 1], to: simd_normalize(delta))
            root.addChild(path)
        }
    }
    func update(_ model: BaduyHomeViewModel, region: MKCoordinateRegion?, zoom: Float, angle: Float, elevation: Float) {
        let target = point(region?.center ?? origin)
        ground.position = [target.x, -1, target.z]
        let span = Float((region?.span.latitudeDelta ?? 0.01) * 111_320)
        let distance = min(8_000, max(80, span * zoom))
        let safeElevation = min(1.35, max(0.35, elevation))
        camera.look(at: target, from: target + [sin(angle) * cos(safeElevation) * distance, sin(safeElevation) * distance, cos(angle) * cos(safeElevation) * distance], relativeTo: nil)
        player.isEnabled = model.location != nil
        if let location = model.location {
            var ground = point(location.coordinate)
            ground.y = terrain.terrainHeight(at: ground)
            player.position = ground
            player.orientation = terrain.buildingPlacement(
                location.coordinate, halfWidth: 4.7, halfDepth: 7.5, rotation: 0
            ).orientation
        }
        for character in BaduyCharacter.allCases {
            let coordinate = model.coordinate(for: character)
            characters[character]?.isEnabled = coordinate != nil
            if let coordinate {
                var ground = point(coordinate)
                ground.y = terrain.terrainHeight(at: ground)
                characters[character]?.position = ground
            }
        }
    }
    @discardableResult
    private func box(_ parent: Entity, _ size: SIMD3<Float>, _ position: SIMD3<Float>, _ color: UIColor) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [UnlitMaterial(color: color)])
        entity.position = position; parent.addChild(entity)
        return entity
    }
}
