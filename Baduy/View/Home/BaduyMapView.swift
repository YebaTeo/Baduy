import SwiftUI
import RealityKit
import UIKit

/// PoC-C67 map renderer: procedural BaduyWorld grid, PoC texture and orbit camera.
struct BaduyMapView: UIViewRepresentable {
    let model: HomeViewModel
    let onLandmark: (MapLandmark) -> Void
    let onCharacter: (BaduyCharacter) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(model: model, onLandmark: onLandmark, onCharacter: onCharacter) }
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        #if targetEnvironment(simulator)
        view.renderOptions.insert(.disableGroundingShadows)
        #endif
        view.environment.background = .color(UIColor(red: 0.94, green: 0.91, blue: 0.82, alpha: 1))
        let c = context.coordinator; c.view = view
        let anchor = AnchorEntity(world: .zero); c.anchor = anchor; view.scene.addAnchor(anchor); c.build()
        anchor.addChild(c.camera); c.updateCamera()
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:))); pan.delegate = c; view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:))); pinch.delegate = c; view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:))))
        return view
    }
    func updateUIView(_ view: ARView, context: Context) { context.coordinator.model = model }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: ARView?; let camera = PerspectiveCamera(); var anchor = AnchorEntity(world: .zero)
        var model: HomeViewModel; let onLandmark: (MapLandmark)->Void; let onCharacter: (BaduyCharacter)->Void
        var angle: Float = 0.35, elevation: Float = 0.82, distance: Float = 1350, lookAt: SIMD3<Float> = [0,0,0]
        private var pinchWorldAnchor: SIMD3<Float>?
        var selectable: [String: MapLandmark] = [:]
        private var locationLabels: [Entity] = []
        let awsTerrain = CibolegerTerrain()
        init(model: HomeViewModel,onLandmark:@escaping(MapLandmark)->Void,onCharacter:@escaping(BaduyCharacter)->Void){self.model=model;self.onLandmark=onLandmark;self.onCharacter=onCharacter}
        func build() {
            if let terrain = try? awsTerrain.entity() { anchor.addChild(terrain) }
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
                #if targetEnvironment(simulator)
                for b in SettlementData.displayedBuildings {
                    let coordinate = BaduyWorld.coordinate(b.position)
                    let ground = awsTerrain.point(coordinate)
                    let surface = awsTerrain.buildingSurface(coordinate, halfWidth: 5.5, halfDepth: 4.5, rotation: b.rotationY)
                    let lumbung = Self.makeSimulatorLumbung()
                    lumbung.name = b.id
                    // Keep the full footprint above the sampled DEM. The terrain
                    // is downsampled for rendering, so a small clearance avoids
                    // z-fighting and prevents the house from being swallowed by
                    // a neighboring DEM triangle.
                    lumbung.position = [ground.x, surface + 2, ground.z]
                    lumbung.orientation = simd_quatf(angle: b.rotationY, axis: [0, 1, 0])
                    if b.id == featuredBuilding?.id, let featuredLumbung {
                        lumbung.name = featuredLumbung.id
                        lumbung.generateCollisionShapes(recursive: true)
                        lumbung.components.set(InputTargetComponent())
                    }
                    anchor.addChild(lumbung)
                }
                return
                #else
                // Flatten the static USD hierarchy once, then share its mesh across houses.
                guard let template = try? await ModelEntity(named: "lumbung.usdc"),
                      var model = template.model else { return }
                for b in SettlementData.displayedBuildings {
                    let lumbung = template.clone(recursive: true)
                    lumbung.name = b.id
                    lumbung.scale = [6, 6, 6]
                    lumbung.orientation = simd_quatf(angle: b.rotationY, axis: [0, 1, 0])
                    let coordinate = BaduyWorld.coordinate(b.position)
                    let ground = awsTerrain.point(coordinate)
                    let surface = awsTerrain.buildingSurface(coordinate, halfWidth: Float(b.size.x), halfDepth: Float(b.size.z), rotation: b.rotationY)
                    lumbung.position = ground
                    // Measure before attaching to the world so the bounds are local.
                    let localBounds = lumbung.visualBounds(relativeTo: lumbung)
                    lumbung.position.y = surface - localBounds.min.y * lumbung.scale.y + 0.2
                    if b.id == featuredBuilding?.id, let featuredLumbung {
                        lumbung.name = featuredLumbung.id
                        lumbung.generateCollisionShapes(recursive: true)
                        lumbung.components.set(InputTargetComponent())
                    }
                    anchor.addChild(lumbung)
                }
                #endif
            }
            for landmark in model.landmarks {
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
            for poi in BaduyLandmark.samples where poi.category != "village" {
                addLocationLabel(poi.title, subtitle: poi.subtitle, coordinate: poi.coordinate)
            }
            for character in BaduyCharacter.allCases { if let c=model.coordinate(for:character){let p=awsTerrain.point(c);let m=ModelEntity(mesh:.generateSphere(radius:5),materials:[UnlitMaterial(color:character == .cowo ? .systemTeal : .systemYellow)]);m.name=character.rawValue;m.position=p+[0,7,0];m.generateCollisionShapes(recursive:true);m.components.set(InputTargetComponent());anchor.addChild(m)} }
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
        #if targetEnvironment(simulator)
        private static func makeSimulatorLumbung() -> ModelEntity {
            let body = MeshResource.generateBox(size: [10, 5, 8])
            let roof = MeshResource.generateBox(size: [11, 0.7, 9])
            let material = UnlitMaterial(color: UIColor(red: 0.72, green: 0.48, blue: 0.22, alpha: 1))
            let root = ModelEntity()
            let base = ModelEntity(mesh: body, materials: [material])
            base.position.y = 2.5
            root.addChild(base)
            let cap = ModelEntity(mesh: roof, materials: [material])
            cap.position.y = 5.35
            cap.orientation = simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
            root.addChild(cap)
            return root
        }
        #endif
        func updateCamera(){let eye=lookAt+SIMD3<Float>(sin(angle)*cos(elevation)*distance,sin(elevation)*distance,cos(angle)*cos(elevation)*distance);camera.look(at:lookAt,from:eye,relativeTo:nil);for label in locationLabels{label.look(at:eye,from:label.position(relativeTo:nil),relativeTo:nil);label.orientation *= simd_quatf(angle:.pi,axis:[0,1,0])}}
        func gestureRecognizer(_ a:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith b:UIGestureRecognizer)->Bool{true}
        @objc func pan(_ g: UIPanGestureRecognizer) { let d = g.translation(in: view); if g.numberOfTouches <= 1 { angle -= Float(d.x) * 0.006; elevation = min(1.4, max(0.25, elevation + Float(d.y) * 0.004)) } else { let s = distance * 0.0012; lookAt.x += cos(angle) * Float(d.x) * s + sin(angle) * Float(d.y) * s; lookAt.z += -sin(angle) * Float(d.x) * s + cos(angle) * Float(d.y) * s }; g.setTranslation(.zero, in: view); updateCamera() }
        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard let view else { return }
            let center = g.location(in: view)
            if g.state == .began { pinchWorldAnchor = worldPoint(at: center) }
            distance = min(3200, max(280, distance / Float(g.scale)))
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
