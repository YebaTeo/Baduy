import RealityKit
import UIKit

enum BaduyLeafMarker {
    static func make() -> Entity {
        let root = Entity()
        root.name = "user_position"

        let leaf = makeLeaf()
        leaf.name = "leaf_marker"
        leaf.position = [0, 0.12, 0]
        root.addChild(leaf)

        let character = makeCharacter()
        character.name = "standing_marker"
        character.isEnabled = false
        root.addChild(character)

        root.generateCollisionShapes(recursive: true)
        return root
    }

    static func setPresentation(_ root: Entity, standing: Bool) {
        if let leaf = root.children.first(where: { $0.name == "leaf_marker" }) {
            leaf.isEnabled = true
            leaf.position = standing ? [0, 7.7, 0] : [0, 0.12, 0]
            leaf.orientation = standing
                ? simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                : simd_quatf()
        }
        root.children.first(where: { $0.name == "standing_marker" })?.isEnabled = false
    }

    static func makeCharacter() -> ModelEntity {
        let root = ModelEntity()
        let cloth = UnlitMaterial(color: UIColor(red: 0.94, green: 0.90, blue: 0.76, alpha: 1))
        let body = ModelEntity(mesh: .generateCylinder(height: 3, radius: 0.9), materials: [cloth])
        body.position.y = 1.5
        root.addChild(body)
        let head = ModelEntity(mesh: .generateSphere(radius: 0.7), materials: [cloth])
        head.position.y = 3.6
        root.addChild(head)
        root.generateCollisionShapes(recursive: true)
        root.components.set(InputTargetComponent())
        return root
    }

    private static func makeLeaf() -> ModelEntity {
        // One curved surface shared by the blade and its veins, so details
        // remain attached when viewed from the side as well as from above.
        func surface(_ t: Float, _ u: Float) -> SIMD3<Float> {
            let arch = sin(.pi * t)
            let width = 4.7 * pow(max(0, arch), 0.85) * (0.82 + 0.18 * t)
            let ripple = 1 + 0.025 * sin(t * .pi * 18)
            let x = u * width * ripple + 0.35 * arch
            let y = 1.25 * arch * (1 - pow(abs(u), 1.3))
                + 0.22 * u * arch + 0.40 * t * t
            return [x, y, 7 - 15 * t]
        }
        let rows = 48, columns = 16
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var materialIndices: [UInt32] = []
        for row in 0...rows {
            for column in 0...columns {
                vertices.append(surface(Float(row) / Float(rows), Float(column) / Float(columns) * 2 - 1))
            }
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let a = UInt32(row * (columns + 1) + column)
                let b = a + 1, c = a + UInt32(columns + 1), d = c + 1
                // Both faces keep the thin blade visible while orbiting.
                indices += [a, b, c, b, d, c, c, b, a, c, d, b]
                let tone: UInt32 = column < columns / 2 ? 0 : 1
                materialIndices += [tone, tone, 2, 2]
            }
        }
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .perFace(materialIndices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else {
            return ModelEntity(
                mesh: .generateBox(size: [6, 0.4, 12]),
                materials: [UnlitMaterial(color: UIColor(red: 0.25, green: 0.38, blue: 0.17, alpha: 1))]
            )
        }
        let leaf = ModelEntity(
            mesh: mesh,
            materials: [
                UnlitMaterial(color: UIColor(red: 0.25, green: 0.38, blue: 0.17, alpha: 1)),
                UnlitMaterial(color: UIColor(red: 0.29, green: 0.44, blue: 0.20, alpha: 1)),
                UnlitMaterial(color: UIColor(red: 0.30, green: 0.40, blue: 0.22, alpha: 1))
            ]
        )
        // Batch every vein into one mesh instead of dozens of entities.
        var veinVertices: [SIMD3<Float>] = []
        var veinIndices: [UInt32] = []
        func vein(from start: SIMD2<Float>, to end: SIMD2<Float>, width: Float) {
            let steps = 16
            for step in 0..<steps {
                let t0 = Float(step) / Float(steps), t1 = Float(step + 1) / Float(steps)
                let uv0 = start + (end - start) * t0
                let uv1 = start + (end - start) * t1
                let a = surface(uv0.x, uv0.y) + SIMD3<Float>(0, 0.045, 0)
                let b = surface(uv1.x, uv1.y) + SIMD3<Float>(0, 0.045, 0)
                let direction = b - a
                let side = simd_normalize(SIMD3<Float>(-direction.z, 0, direction.x))
                let w0 = width * (1 - 0.75 * t0) / 2
                let w1 = width * (1 - 0.75 * t1) / 2
                let offset = UInt32(veinVertices.count)
                veinVertices += [a - side * w0, a + side * w0, b - side * w1, b + side * w1]
                veinIndices += [offset, offset + 1, offset + 2, offset + 1, offset + 3, offset + 2]
            }
        }
        vein(from: [0.02, 0], to: [0.98, 0], width: 0.22)
        for index in 0..<8 {
            let t = 0.12 + Float(index) * 0.09
            for side: Float in [-1, 1] {
                vein(from: [t, 0], to: [min(t + 0.17, 0.95), side * 0.94], width: 0.10)
                for branch in 1...2 {
                    let u = Float(branch) * 0.28
                    vein(from: [t + 0.17 * u, side * u],
                         to: [min(t + 0.17 * u + 0.09, 0.97), side * (u + 0.22)], width: 0.035)
                }
            }
        }
        var veins = MeshDescriptor()
        veins.positions = MeshBuffers.Positions(veinVertices)
        veins.primitives = .triangles(veinIndices)
        if let veinMesh = try? MeshResource.generate(from: [veins]) {
            leaf.addChild(ModelEntity(mesh: veinMesh, materials: [
                UnlitMaterial(color: UIColor(red: 0.36, green: 0.48, blue: 0.22, alpha: 1))
            ]))
        }
        return leaf
    }
}
