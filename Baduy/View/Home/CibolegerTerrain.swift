import MapKit
import RealityKit
import UIKit

/// Offline Terrarium DEM, z12/x3256/y2123. Heights are metres, without exaggeration.
@MainActor
final class CibolegerTerrain {
    private let origin = MKMapPoint(MapLandmark.baduyPoints[0].coordinate)
    private let tileSize = MKMapSize.world.width / 4096
    private let scale = MKMetersPerMapPointAtLatitude(MapLandmark.baduyPoints[0].coordinate.latitude)
    private var demValues = [Int](repeating: 0, count: 256 * 256)
    private var baseElevation: Float = 0
    private let verticalScale: Float = 0.03
    // Keep placement samples aligned with the rendered DEM mesh.
    private let gridSamples = (0..<128).map { Int((Double($0) / 127 * 255).rounded()) }
    private var heightMap: [Int: Float] = [:]
    private(set) var available = false
    init() {
        guard let url = Bundle.main.url(forResource: "ciboleger-dem", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dem = try? JSONDecoder().decode(DEM.self, from: data),
              dem.width == 256, dem.height == 256, dem.values.count == 256 * 256 else { return }
        demValues = dem.values
        // RealityKit scene coordinates are local to the first DEM sample.
        // Keep the terrain near y=0 instead of placing it at absolute AMSL.
        baseElevation = Float(dem.values[0]) / Float(dem.scale)
        available = true
    }
    private func elevation(_ x: Int, _ y: Int) -> Float {
        (Float(demValues[y * 256 + x]) / 100 - baseElevation) * verticalScale
    }
    private struct DEM: Decodable { let width: Int; let height: Int; let scale: Int; let values: [Int] }
    func height(_ p: MKMapPoint) -> Float {
        let x = (p.x / tileSize - 3256) * 256 - 0.5
        let y = (p.y / tileSize - 2123) * 256 - 0.5
        guard available, x >= 0, y >= 0, x <= 255, y <= 255 else { return 0 }
        let ix = min(gridSamples.lastIndex(where: { Double($0) <= x })!, gridSamples.count - 2)
        let iy = min(gridSamples.lastIndex(where: { Double($0) <= y })!, gridSamples.count - 2)
        let x0 = gridSamples[ix], x1 = gridSamples[ix + 1]
        let y0 = gridSamples[iy], y1 = gridSamples[iy + 1]
        let dx = Float((x - Double(x0)) / Double(x1 - x0))
        let dy = Float((y - Double(y0)) / Double(y1 - y0))
        let key = (iy << 8) | ix
        if dx == 0 && dy == 0, let cached = heightMap[key] { return cached }
        let a = elevation(x0, y0), b = elevation(x1, y0)
        let c = elevation(x0, y1), d = elevation(x1, y1)
        let result: Float = dx + dy <= 1 ? a + (b - a) * dx + (c - a) * dy : d + (c - d) * (1 - dx) + (b - d) * (1 - dy)
        if dx == 0 && dy == 0 { heightMap[key] = result }
        return result
    }
    /// Height of the highest DEM sample under a building footprint.
    func buildingSurface(_ coordinate: CLLocationCoordinate2D, halfWidth: Float, halfDepth: Float, rotation: Float) -> Float {
        let center = MKMapPoint(coordinate)
        let c = cos(rotation), s = sin(rotation)
        let samples = [-1.0, -0.5, 0.0, 0.5, 1.0]
        var heights: [Float] = []
        for u in samples { for v in samples {
            let localX = Double(u) * Double(halfWidth), localZ = Double(v) * Double(halfDepth)
            let east = (localX * Double(c) - localZ * Double(s)) / scale
            let north = (localX * Double(s) + localZ * Double(c)) / scale
            heights.append(height(MKMapPoint(x: center.x + east, y: center.y - north)))
        }}
        return heights.max() ?? height(center)
    }
    func point(_ coordinate: CLLocationCoordinate2D) -> SIMD3<Float> {
        let p = MKMapPoint(coordinate)
        return [Float((p.x-origin.x)*scale), height(p), Float((p.y-origin.y)*scale)]
    }
    func entity() throws -> Entity {
        var vertices: [SIMD3<Float>] = [], indices: [UInt32] = [], uv: [SIMD2<Float>] = []
        var contours: [SIMD3<Float>] = [], contourIndices: [UInt32] = []
        let samples = gridSamples.count
        for y in 0..<samples { for x in 0..<samples {
            let sourceX = gridSamples[x]
            let sourceY = gridSamples[y]
            let p = MKMapPoint(x: (3256 + (Double(sourceX)+0.5)/256)*tileSize,
                               y: (2123 + (Double(sourceY)+0.5)/256)*tileSize)
            vertices.append([Float((p.x-origin.x)*scale), elevation(sourceX,sourceY), Float((p.y-origin.y)*scale)])
            uv.append([Float(x) / Float(samples - 1), 1 - Float(y) / Float(samples - 1)])
        }}
        for y in 0..<(samples - 1) { for x in 0..<(samples - 1) {
            let a = UInt32(y*samples+x), b = a+1, c = a+UInt32(samples), d = c+1
            indices += [a,c,b,b,c,d]
            // Triangle intersections avoid ambiguous marching-squares saddle cases.
            for tri in [[a,c,b],[b,c,d]] {
                let v = tri.map { vertices[Int($0)] }
                let low = v.map(\.y).min()!, high = v.map(\.y).max()!
                var level = (floor(low/20)+1)*20
                while level <= high {
                    var hits: [SIMD3<Float>] = []
                    for edge in 0..<3 {
                        let p = v[edge], q = v[(edge+1)%3]
                        if (p.y < level && q.y >= level) || (q.y < level && p.y >= level) {
                            hits.append(p + (q-p)*((level-p.y)/(q.y-p.y)) + [0,0.45,0])
                        }
                    }
                    if hits.count == 2 { Self.ribbon(hits[0], hits[1], width: 0.65, vertices: &contours, indices: &contourIndices) }
                    level += 20
                }
            }
        }}
        let result = Entity()
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        descriptor.primitives = .triangles(indices)
        let terrainMesh = try MeshResource.generate(from: [descriptor])
        if let texture = try? TerrainTexture.make() {
            var material = UnlitMaterial(color: .white)
            material.color = .init(tint: .white, texture: .init(texture))
            result.addChild(ModelEntity(mesh: terrainMesh, materials: [material]))
        } else {
            result.addChild(ModelEntity(mesh: terrainMesh, materials: [UnlitMaterial(color: UIColor(red:0.035,green:0.09,blue:0.16,alpha:1))]))
        }
        // Keep the contour overlay lightweight for Metal Simulator.
        if !contourIndices.isEmpty && contourIndices.count <= 12_000 {
            result.addChild(try Self.mesh(contours, contourIndices, color: UIColor(red:0.16,green:0.26,blue:0.33,alpha:1)))
        }
        try addRoads(to: result)
        return result
    }
    private func addRoads(to parent: Entity) throws {
        guard let url = Bundle.main.url(forResource: "ciboleger", withExtension: "geojson") else { return }
        let collection = try JSONDecoder().decode(Collection.self, from: Data(contentsOf: url))
        var vertices: [SIMD3<Float>] = [], indices: [UInt32] = []
        for feature in collection.features where feature.properties.kind == "highway" {
            let points = feature.geometry.coordinates.map { point(CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])) }
            let width: Float = ["path", "footway", "track", "bridleway", "steps"].contains(feature.properties.value) ? 2.2 : 4.5
            for (a, b) in zip(points, points.dropFirst()) {
                var start = a, end = b
                start.y += 1.1; end.y += 1.1
                Self.ribbon(start, end, width: width, vertices: &vertices, indices: &indices)
            }
        }
        if !indices.isEmpty {
            parent.addChild(try Self.mesh(vertices, indices, color: UIColor(red: 0.82, green: 0.76, blue: 0.60, alpha: 1)))
        }
    }
    private struct Collection: Decodable { let features: [Feature] }
    private struct Feature: Decodable {
        struct Properties: Decodable { let kind: String; let value: String }
        struct Geometry: Decodable { let coordinates: [[Double]] }
        let properties: Properties
        let geometry: Geometry
    }
    private func addGeography(to parent: Entity) throws {
        guard let url = Bundle.main.url(forResource: "ciboleger", withExtension: "geojson") else { return }
        let collection = try JSONDecoder().decode(Collection.self, from: Data(contentsOf: url))
        for kind in ["building", "highway", "waterway"] {
            var vertices: [SIMD3<Float>] = [], indices: [UInt32] = []
            var roofs: [SIMD3<Float>] = [], roofIndices: [UInt32] = []
            for feature in collection.features where feature.properties.kind == kind {
                let points = feature.geometry.coordinates.map { point(CLLocationCoordinate2D(latitude:$0[1], longitude:$0[0])) }
                if kind == "building", points.count > 3, points.first == points.last {
                    Self.roof(Array(points.dropLast()).map { $0 + [0,6.7,0] }, vertices: &roofs, indices: &roofIndices)
                }
                for (a,b) in zip(points,points.dropFirst()) {
                    let length = simd_length(b-a)
                    let steps = max(1,Int(ceil(length/10)))
                    for step in 0..<steps {
                        var p = a+(b-a)*Float(step)/Float(steps)
                        var q = a+(b-a)*Float(step+1)/Float(steps)
                        // Resample every ten metres so long OSM segments follow the DEM.
                        for isEnd in [false,true] {
                            var v = isEnd ? q : p
                            v.y = height(MKMapPoint(x:origin.x+Double(v.x)/scale,y:origin.y+Double(v.z)/scale)) + 0.7
                            if isEnd { q=v } else { p=v }
                        }
                        if kind == "building" {
                            let i = UInt32(vertices.count)
                            // Six metres is illustrative; footprints are mapped, heights are not surveyed.
                            vertices += [p,q,p+[0,6,0],q+[0,6,0]]
                            indices += [i,i+2,i+1,i+1,i+2,i+3,i+1,i+2,i,i+3,i+2,i+1]
                            Self.ribbon(p+[0,6.1,0],q+[0,6.1,0],width:0.65,vertices:&vertices,indices:&indices)
                        } else {
                            let width: Float = kind == "waterway" ? 3 : (["path","footway","track"].contains(feature.properties.value) ? 1.7 : 4)
                            Self.ribbon(p,q,width:width,vertices:&vertices,indices:&indices)
                        }
                    }
                }
            }
            if !indices.isEmpty {
                let color: UIColor = kind == "waterway" ? UIColor(red:0.28,green:0.47,blue:0.58,alpha:1) :
                    kind == "highway" ? UIColor(red:0.78,green:0.75,blue:0.65,alpha:1) : UIColor(red:0.40,green:0.48,blue:0.52,alpha:1)
                parent.addChild(try Self.mesh(vertices, indices, color: color))
            }
            if !roofIndices.isEmpty {
                parent.addChild(try Self.mesh(roofs,roofIndices,color:UIColor(red:0.095,green:0.18,blue:0.27,alpha:1)))
            }
        }
    }
    // Ear clipping preserves concave OSM footprints instead of filling a bounding box.
    private static func roof(_ polygon: [SIMD3<Float>], vertices: inout [SIMD3<Float>], indices: inout [UInt32]) {
        func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Float {
            (b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x)
        }
        var remaining = Array(polygon.indices)
        let area = polygon.indices.reduce(Float(0)) { total,i in
            let a=polygon[i], b=polygon[(i+1)%polygon.count]
            return total+a.x*b.z-b.x*a.z
        }
        if area < 0 { remaining.reverse() }
        var triangles: [UInt32] = []
        while remaining.count > 2 {
            var found = false
            for i in remaining.indices {
                let a=remaining[(i+remaining.count-1)%remaining.count], b=remaining[i], c=remaining[(i+1)%remaining.count]
                guard cross(polygon[a],polygon[b],polygon[c]) > 0.001 else { continue }
                let occupied = remaining.contains { p in
                    p != a && p != b && p != c && cross(polygon[a],polygon[b],polygon[p]) >= 0 &&
                    cross(polygon[b],polygon[c],polygon[p]) >= 0 && cross(polygon[c],polygon[a],polygon[p]) >= 0
                }
                if !occupied {
                    triangles += [UInt32(a),UInt32(c),UInt32(b)]
                    remaining.remove(at:i); found=true; break
                }
            }
            if !found { return } // Degenerate geometry stays an outline.
        }
        let offset = UInt32(vertices.count)
        vertices += polygon
        indices += triangles.map { $0+offset }
    }
    static func ribbon(_ a: SIMD3<Float>, _ b: SIMD3<Float>, width: Float, vertices: inout [SIMD3<Float>], indices: inout [UInt32]) {
        let delta = b-a
        guard simd_length(delta) > 0.001 else { return }
        let side = simd_normalize(SIMD3<Float>(-delta.z,0,delta.x))*width/2
        let i = UInt32(vertices.count)
        vertices += [a-side,a+side,b-side,b+side]
        indices += [i,i+1,i+2,i+1,i+3,i+2]
    }
    static func mesh(_ vertices: [SIMD3<Float>], _ indices: [UInt32], color: UIColor, lit: Bool = false) throws -> ModelEntity {
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.primitives = .triangles(indices)
        let resource = try MeshResource.generate(from: [descriptor])
        if lit { return ModelEntity(mesh: resource, materials: [SimpleMaterial(color: color, roughness: 1, isMetallic: false)]) }
        return ModelEntity(mesh: resource, materials: [UnlitMaterial(color: color)])
    }
}
