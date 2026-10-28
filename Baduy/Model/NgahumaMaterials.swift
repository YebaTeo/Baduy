import RealityKit
import UIKit

/// Generated color textures are shared by all instances. These are not measured PBR scans.
@MainActor
struct NgahumaMaterials {
    let soil: TextureResource
    let ash: TextureResource
    let grass: TextureResource
    let seedling: TextureResource
    let panorama: TextureResource
    let flame: TextureResource

    static func load() async throws -> Self {
        func texture(_ name: String) async throws -> TextureResource {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try await TextureResource(contentsOf: url, options: .init(semantic: .color))
        }
        let soil = try await texture("ngahuma-soil")
        let ash = try await texture("ngahuma-ash")
        let grass = try await texture("ngahuma-grass")
        let seedling = try await texture("ngahuma-seedling")
        let panorama = try await texture("ngahuma-panorama")
        let flame = try await texture("ngahuma-flame")
        return Self(soil: soil, ash: ash, grass: grass, seedling: seedling, panorama: panorama, flame: flame)
    }

    func earth(burned: Bool = false) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: .init(burned ? ash : soil))
        material.roughness = .init(floatLiteral: 0.96)
        material.specular = .init(floatLiteral: 0.12)
        return material
    }

    func foliage(young: Bool = false) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: .init(young ? seedling : grass))
        material.roughness = .init(floatLiteral: 0.9)
        material.specular = .init(floatLiteral: 0.1)
        material.faceCulling = .none
        // Cutout rendering preserves gaps and depth without sorting transparent cards.
        material.opacityThreshold = 0.25
        return material
    }

    func clump(height: Float, young: Bool = false) -> Entity {
        let clump = Entity()
        let material = foliage(young: young)
        let mesh = MeshResource.generatePlane(width: height, height: height)
        for index in 0..<3 {
            let card = ModelEntity(mesh: mesh, materials: [material])
            card.position.y = height * 0.48
            card.orientation = simd_quatf(angle: Float(index) * .pi / 3, axis: [0, 1, 0])
            clump.addChild(card)
        }
        return clump
    }

    /// A low-amplitude mesh with metre-scaled UVs, keeping the interactive ring level.
    func terrain() throws -> ModelEntity {
        let steps = 64
        let span: Float = 80
        var vertices: [SIMD3<Float>] = []
        var uv: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        for z in 0...steps {
            for x in 0...steps {
                let px = Float(x) / Float(steps) * span - span / 2
                let pz = Float(z) / Float(steps) * span - span / 2
                let radius = sqrt(px * px + pz * pz)
                let amplitude = min(1, max(0, (radius - 3.5) / 8))
                let height = amplitude * (sin(px * 0.41) * cos(pz * 0.32) * 0.28 - 0.35)
                vertices.append([px, height - 0.012, pz])
                uv.append([px / 2, pz / 2])
                if x < steps && z < steps {
                    let a = UInt32(z * (steps + 1) + x)
                    let b = a + UInt32(steps + 1)
                    indices += [a, b, a + 1, a + 1, b, b + 1]
                }
            }
        }
        var descriptor = MeshDescriptor(name: "Ngahuma earth")
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        descriptor.primitives = .triangles(indices)
        return ModelEntity(mesh: try MeshResource.generate(from: [descriptor]), materials: [earth()])
    }
}
