import SwiftUI
import RealityKit
import UIKit

enum BaduyCameraMode: String, CaseIterable, Identifiable {
    case topDown
    case thirdPerson
    var id: Self { self }
}

/// PoC-C67 map renderer: procedural BaduyWorld grid, PoC texture and orbit camera.
struct BaduyMapView: UIViewRepresentable {
    let model: HomeViewModel
    let cameraMode: BaduyCameraMode
    let onLandmark: (MapLandmark) -> Void
    let onCharacter: (BaduyCharacter) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(model: model, cameraMode: cameraMode, onLandmark: onLandmark, onCharacter: onCharacter) }
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        #if targetEnvironment(simulator)
        view.renderOptions.insert(.disableGroundingShadows)
        #endif
        view.environment.background = .color(UIColor(red: 0.94, green: 0.91, blue: 0.82, alpha: 1))
        let c = context.coordinator; c.view = view
        let anchor = AnchorEntity(world: .zero); c.anchor = anchor; view.scene.addAnchor(anchor)
        Task { @MainActor [weak c] in
            let texture = try? await TerrainTexture.make()
            guard let c else { return }
            await c.awsTerrain.loadRemoteElevation()
            guard c.view != nil else { return }
            c.build(texture: texture)
        }
        anchor.addChild(c.camera); c.updateCamera()
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:))); pan.delegate = c; view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:))); pinch.delegate = c; view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:))))
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.model = model
        context.coordinator.updatePlayerPosition()
        context.coordinator.setCameraMode(cameraMode)
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: ARView?; let camera = PerspectiveCamera(); var anchor = AnchorEntity(world: .zero)
        var model: HomeViewModel; let onLandmark: (MapLandmark)->Void; let onCharacter: (BaduyCharacter)->Void
        var angle: Float = 0.35, elevation: Float = 0.82, distance: Float = 820, lookAt: SIMD3<Float> = [0,0,0]
        private var pinchWorldAnchor: SIMD3<Float>?
        private var activeCameraMode: BaduyCameraMode
        private var cameraIsConfigured = false
        private var playerMarker: ModelEntity?
        var selectable: [String: MapLandmark] = [:]
        private var locationLabels: [Entity] = []
        let awsTerrain = CibolegerTerrain()
        init(model: HomeViewModel,cameraMode:BaduyCameraMode,onLandmark:@escaping(MapLandmark)->Void,onCharacter:@escaping(BaduyCharacter)->Void){self.model=model;self.activeCameraMode=cameraMode;self.onLandmark=onLandmark;self.onCharacter=onCharacter}
        func build(texture: TextureResource?) {
            if let terrain = try? awsTerrain.entity(texture: texture) { anchor.addChild(terrain) }
            let featuredBuilding = SettlementData.displayedBuildings.min {
                simd_length_squared(SIMD2<Float>($0.position.x, $0.position.z)) <
                simd_length_squared(SIMD2<Float>($1.position.x, $1.position.z))
            }
            let featuredLumbung: MapLandmark? = featuredBuilding.map { building in
                MapLandmark(
                    id: "lumbung_padi_demo",
                    name: "Lumbung Padi",
                    coordinate: BaduyWorld.coordinate(building.position),
                    radius: 25,
                    detail: "Kenali fungsi lumbung padi tradisional dalam kehidupan masyarakat Kanekes."
                )
            }
            if let featuredLumbung {
                selectable[featuredLumbung.id] = featuredLumbung
                addLocationLabel(featuredLumbung.name, subtitle: "Ketuk untuk menjelajah", coordinate: featuredLumbung.coordinate)
            }
            Task { @MainActor in
                // Build one lightweight procedural house and reuse its primitive
                // meshes for every settlement building. This avoids loading a
                // heavyweight USD asset while keeping the lumbung silhouette.
                let template = Self.makeProceduralLumbung()
                for (index, b) in SettlementData.displayedBuildings.enumerated() {
                    if index.isMultiple(of: 32) { await Task.yield() }
                    let coordinate = BaduyWorld.coordinate(b.position)
                    let ground = awsTerrain.point(coordinate)
                    let placement = awsTerrain.buildingPlacement(
                        coordinate,
                        halfWidth: 3.7 * template.scale.x,
                        halfDepth: 2.8 * template.scale.z,
                        rotation: b.rotationY
                    )
                    let lumbung = template.clone(recursive: true)
                    lumbung.name = b.id
                    // The template's posts start at local y = 0. Fit the
                    // whole house to the local terrain plane so it does not
                    // float above a slope or remain unnaturally vertical.
                    lumbung.position = [ground.x, placement.surface, ground.z]
                    lumbung.orientation = placement.orientation

                    // Ground each foot against the actual DEM. A center-point
                    // placement can still leave a foot floating when the terrain
                    // changes faster than the fitted plane.
                    let footPositions: [SIMD3<Float>] = [
                        [-3.7, 0, -2.8], [3.7, 0, -2.8],
                        [-3.7, 0, 2.8], [3.7, 0, 2.8]
                    ]
                    let footCorrections = footPositions.map { foot in
                        let scaledFoot = SIMD3<Float>(
                            foot.x * lumbung.scale.x,
                            foot.y * lumbung.scale.y,
                            foot.z * lumbung.scale.z
                        )
                        let worldOffset = Self.rotated(scaledFoot, by: lumbung.orientation)
                        let worldFoot = lumbung.position + worldOffset
                        let terrainY = awsTerrain.terrainHeight(at: [worldFoot.x, 0, worldFoot.z])
                        return terrainY - worldFoot.y
                    }
                    // Seat the lowest-ground foot too; a small intersection on
                    // uneven ground is preferable to a visible gap below a post.
                    lumbung.position.y += footCorrections.min() ?? 0

                    if b.id == featuredBuilding?.id, let featuredLumbung {
                        lumbung.name = featuredLumbung.id
                        lumbung.generateCollisionShapes(recursive: true)
                        lumbung.components.set(InputTargetComponent())
                    }
                    anchor.addChild(lumbung)
                }
            }
            for landmark in model.landmarks where BaduyWorld.isInsideRealityArea(landmark.coordinate) {
                let p = awsTerrain.point(landmark.coordinate)
                let h = ModelEntity(mesh: .generateBox(size: [18, 8, 12]), materials: [UnlitMaterial(color: UIColor(red: 0.07, green: 0.19, blue: 0.28, alpha: 1))])
                h.name = landmark.id
                h.position = p + [0, 4, 0]
                h.generateCollisionShapes(recursive: true)
                h.components.set(InputTargetComponent())
                anchor.addChild(h)
                selectable[landmark.id] = landmark
                addLocationLabel(landmark.name, subtitle: "Kampung Baduy", coordinate: landmark.coordinate)
            }
            // Add named POIs that are not already represented by a village label.
            for poi in BaduyLandmark.samples where poi.category != "village" && BaduyWorld.isInsideRealityArea(poi.coordinate) {
                addLocationLabel(poi.title, subtitle: poi.subtitle, coordinate: poi.coordinate)
            }
            for character in BaduyCharacter.allCases { if let c=model.coordinate(for:character), BaduyWorld.isInsideRealityArea(c){let p=awsTerrain.point(c);let m=ModelEntity(mesh:.generateSphere(radius:5),materials:[UnlitMaterial(color:character == .cowo ? .systemTeal : .systemYellow)]);m.name=character.rawValue;
                m.position=p+[0,7,0];m.generateCollisionShapes(recursive:true);m.components.set(InputTargetComponent());anchor.addChild(m)} }
            let player = ModelEntity(
                mesh: .generateSphere(radius: 4),
                materials: [UnlitMaterial(color: UIColor(red: 0.20, green: 0.72, blue: 0.76, alpha: 1))]
            )
            player.name = "user_position"
            playerMarker = player
            anchor.addChild(player)
            updatePlayerPosition()
            player.isEnabled = activeCameraMode == .thirdPerson
            setCameraMode(activeCameraMode)
        }

        func setCameraMode(_ mode: BaduyCameraMode) {
            let changed = mode != activeCameraMode || !cameraIsConfigured
            activeCameraMode = mode
            playerMarker?.isEnabled = mode == .thirdPerson
            updatePlayerPosition()
            guard changed else {
                if mode == .thirdPerson { updateCamera() }
                return
            }
            cameraIsConfigured = true
            switch mode {
            case .topDown:
                angle = 0
                elevation = 1.18
                // Frame Spot 5 and the first southbound settlements on entry.
                // Previously this centered on Ciboleger, leaving the newly
                // bundled corridor just beyond the lower edge of the view.
                distance = 1_150
                let corridorCenter = CLLocationCoordinate2D(latitude: -6.61050, longitude: 106.22350)
                lookAt = awsTerrain.point(corridorCenter)
            case .thirdPerson:
                angle = 0
                elevation = 0.32
                distance = 58
                if let playerMarker {
                    let player = playerMarker.position(relativeTo: nil)
                    lookAt = player + [0, 5, -16]
                }
            }
            updateCamera()
        }

        func updatePlayerPosition() {
            guard let playerMarker else { return }
            let requestedCoordinate = model.location?.coordinate ?? MapLandmark.baduyPoints[0].coordinate
            // Outside the mapped Baduy corridor, start the 3D experience at
            // Terminal Ciboleger rather than placing the player on empty space.
            let coordinate = BaduyWorld.isInsideRealityArea(requestedCoordinate)
                ? requestedCoordinate
                : MapLandmark.baduyPoints[0].coordinate
            let ground = awsTerrain.point(coordinate)
            playerMarker.position = ground + [0, 5, 0]
            if activeCameraMode == .thirdPerson {
                lookAt = ground + [0, 5, -16]
            }
        }

        private func addLocationLabel(_ title: String, subtitle: String, coordinate: CLLocationCoordinate2D) {
            let root = Entity()
            root.name = "label_\(title)"

            let titleMesh = MeshResource.generateText(
                title,
                extrusionDepth: 0.12,
                font: .systemFont(ofSize: 9, weight: .bold),
                containerFrame: CGRect(x: 0, y: 0, width: 88, height: 12),
                alignment: .center,
                lineBreakMode: .byTruncatingTail
            )
            let titleEntity = ModelEntity(
                mesh: titleMesh,
                materials: [UnlitMaterial(color: UIColor(red: 0.05, green: 0.20, blue: 0.31, alpha: 1))]
            )
            titleEntity.position = [-44, 1.2, 0.3]
            root.addChild(titleEntity)

            let subtitleMesh = MeshResource.generateText(
                subtitle,
                extrusionDepth: 0.06,
                font: .systemFont(ofSize: 4.2, weight: .medium),
                containerFrame: CGRect(x: 0, y: 0, width: 88, height: 7),
                alignment: .center,
                lineBreakMode: .byTruncatingTail
            )
            let subtitleEntity = ModelEntity(
                mesh: subtitleMesh,
                materials: [UnlitMaterial(color: UIColor(red: 0.37, green: 0.39, blue: 0.31, alpha: 1))]
            )
            subtitleEntity.position = [-44, -5.2, 0.3]
            root.addChild(subtitleEntity)

            let plate = ModelEntity(
                mesh: .generateBox(size: [94, 18, 0.7], cornerRadius: 2.5),
                materials: [UnlitMaterial(color: UIColor(red: 0.98, green: 0.93, blue: 0.80, alpha: 0.96))]
            )
            plate.position = [0, 0, 0]
            root.addChild(plate)
            // Keep text in front of the plate regardless of draw order.
            titleEntity.position.z = 0.5
            subtitleEntity.position.z = 0.5

            let ground = awsTerrain.point(coordinate)
            let nearbyLabelCount = locationLabels.filter {
                let p = $0.position(relativeTo: nil)
                return simd_distance(SIMD2<Float>(p.x, p.z), SIMD2<Float>(ground.x, ground.z)) < 110
            }.count
            root.position = ground + [0, 24 + Float(nearbyLabelCount) * 20, 0]
            anchor.addChild(root)
            locationLabels.append(root)
        }
        private static func makeProceduralLumbung() -> ModelEntity {
            let wood = UnlitMaterial(color: UIColor(red: 0.29, green: 0.19, blue: 0.11, alpha: 1))
            let wovenWall = UnlitMaterial(color: UIColor(red: 0.57, green: 0.40, blue: 0.23, alpha: 1))
            let thatch = UnlitMaterial(color: UIColor(red: 0.78, green: 0.64, blue: 0.38, alpha: 1))

            let root = ModelEntity()
            // Keep the illustrative house smaller than the mapped terrain cells.
            root.scale = [0.45, 0.45, 0.45]
            let bodyMesh = MeshResource.generateBox(size: [9.5, 4.6, 7.4], cornerRadius: 0.12)
            let postMesh = MeshResource.generateBox(size: [0.65, 3.8, 0.65], cornerRadius: 0.08)
            let floorMesh = MeshResource.generateBox(size: [10.4, 0.45, 8.2], cornerRadius: 0.08)
            let roofMesh = MeshResource.generateBox(size: [5.8, 0.42, 8.8], cornerRadius: 0.08)
            let ridgeMesh = MeshResource.generateBox(size: [0.75, 0.35, 8.9], cornerRadius: 0.06)

            let body = ModelEntity(mesh: bodyMesh, materials: [wovenWall])
            body.position.y = 4.7
            root.addChild(body)

            let floor = ModelEntity(mesh: floorMesh, materials: [wood])
            floor.position.y = 2.0
            root.addChild(floor)

            for x: Float in [-3.7, 3.7] {
                for z: Float in [-2.8, 2.8] {
                    let post = ModelEntity(mesh: postMesh, materials: [wood])
                    post.position = [x, 1.9, z]
                    root.addChild(post)
                }
            }

            for side: Float in [-1, 1] {
                let roof = ModelEntity(mesh: roofMesh, materials: [thatch])
                roof.position = [side * 2.25, 7.65, 0]
                roof.orientation = simd_quatf(angle: side * -0.52, axis: [0, 0, 1])
                root.addChild(roof)
            }

            let ridge = ModelEntity(mesh: ridgeMesh, materials: [wood])
            ridge.position.y = 9.05
            root.addChild(ridge)

            return root
        }

        private static func rotated(_ vector: SIMD3<Float>, by rotation: simd_quatf) -> SIMD3<Float> {
            let quaternionVector = SIMD3<Float>(
                rotation.vector.x,
                rotation.vector.y,
                rotation.vector.z
            )
            let twiceCross = 2 * simd_cross(quaternionVector, vector)
            return vector + rotation.vector.w * twiceCross + simd_cross(quaternionVector, twiceCross)
        }

        func updateCamera(){let eye=lookAt+SIMD3<Float>(sin(angle)*cos(elevation)*distance,sin(elevation)*distance,cos(angle)*cos(elevation)*distance);camera.look(at:lookAt,from:eye,relativeTo:nil);for label in locationLabels{label.look(at:eye,from:label.position(relativeTo:nil),relativeTo:nil);label.orientation *= simd_quatf(angle:.pi,axis:[0,1,0])}}
        func gestureRecognizer(_ a:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith b:UIGestureRecognizer)->Bool{true}
        @objc func pan(_ g: UIPanGestureRecognizer) { let d = g.translation(in: view); if g.numberOfTouches <= 1 { angle -= Float(d.x) * 0.006; let upper:Float=activeCameraMode == .topDown ? 1.4 : 0.72;elevation=min(upper,max(0.16,elevation+Float(d.y)*0.004)) } else if activeCameraMode == .topDown { let s = distance * 0.0012; lookAt.x += cos(angle) * Float(d.x) * s + sin(angle) * Float(d.y) * s; lookAt.z += -sin(angle) * Float(d.x) * s + cos(angle) * Float(d.y) * s;lookAt.x=min(2200,max(-950,lookAt.x));lookAt.z=min(5400,max(-250,lookAt.z)) }; g.setTranslation(.zero, in: view); updateCamera() }
        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard let view else { return }
            let center = g.location(in: view)
            if g.state == .began { pinchWorldAnchor = worldPoint(at: center) }
            let limits: ClosedRange<Float> = activeCameraMode == .topDown ? 280...3200 : 28...120
            distance = min(limits.upperBound, max(limits.lowerBound, distance / Float(g.scale)))
            g.scale = 1
            updateCamera()
            if let anchor = pinchWorldAnchor, let after = worldPoint(at: center) {
                // Move the look-at point so the geographic point under the
                // fingers remains under the fingers while zooming.
                lookAt += anchor - after
                updateCamera()
            }
            if g.state == .ended || g.state == .cancelled { pinchWorldAnchor = nil }
        }
        private func worldPoint(at screenPoint: CGPoint) -> SIMD3<Float>? {
            guard let view, let ray = view.ray(through: screenPoint), abs(ray.direction.y) > 0.0001 else { return nil }
            let t = -ray.origin.y / ray.direction.y
            guard t >= 0 else { return nil }
            return ray.origin + ray.direction * t
        }
        @objc func tap(_ g:UITapGestureRecognizer){guard let view else{return};var entity:Entity?=view.entity(at:g.location(in:view));while let current=entity{if let l=selectable[current.name]{onLandmark(l);return};if let c=BaduyCharacter.allCases.first(where:{$0.rawValue==current.name}){onCharacter(c);return};entity=current.parent}}
    }
}
