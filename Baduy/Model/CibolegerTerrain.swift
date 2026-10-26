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
    // Render a denser mesh from the same DEM samples. The extra vertices are
    // interpolated from the source data, so no decorative edge geometry is
    // needed to hide the boundary.
    private let gridSamples = Array(0...255)
    private let renderSamples = Array(0...384)
    private var heightMap: [Int: Float] = [:]
    private var demnasGrid: DEMNASLoader.Grid?
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

    func loadRemoteElevation() async {
        let loader = DEMNASLoader()
        guard let grid = try? await loader.load(for: BaduyWorld.realityArea) else {
            return
        }
        demnasGrid = grid
        heightMap.removeAll()
    }

    private func elevation(_ x: Int, _ y: Int) -> Float {
        (Float(demValues[y * 256 + x]) / 100 - baseElevation) * verticalScale
    }
    private struct DEM: Decodable { let width: Int; let height: Int; let scale: Int; let values: [Int] }
    func height(_ p: MKMapPoint) -> Float {
        if let demnasGrid, let remoteHeight = demnasGrid.height(at: p.coordinate) {
            return (remoteHeight - demnasGrid.baseElevation) * verticalScale
        }
        let x = (p.x / tileSize - 3256) * 256 - 0.5
        let y = (p.y / tileSize - 2123) * 256 - 0.5
        guard available, x >= 0, y >= 0, x <= 255, y <= 255 else { return 0 }
        let ix = min(Int(x), 254)
        let iy = min(Int(y), 254)
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

    /// Samples the same DEM used by the terrain mesh at a local world position.
    func terrainHeight(at localPoint: SIMD3<Float>) -> Float {
        renderedHeight(at: localPoint)
    }

    /// Interpolate the actual rendered triangles, rather than the source DEM grid.
    private func renderedHeight(at localPoint: SIMD3<Float>) -> Float {
        let p = MKMapPoint(coordinate(localPoint))
        let cells = Double(renderSamples.count - 1)
        let gx = min(max(((p.x / tileSize - 3256) * 256 - 0.5) / 255 * cells, 0), cells)
        let gy = min(max(((p.y / tileSize - 2123) * 256 - 0.5) / 255 * cells, 0), cells)
        let ix = min(Int(gx), Int(cells) - 1), iy = min(Int(gy), Int(cells) - 1)
        func sample(_ x: Int, _ y: Int) -> Float {
            height(MKMapPoint(
                x: (3256 + (Double(x) / cells * 255 + 0.5) / 256) * tileSize,
                y: (2123 + (Double(y) / cells * 255 + 0.5) / 256) * tileSize
            ))
        }
        let dx = Float(gx - Double(ix)), dy = Float(gy - Double(iy))
        let a = sample(ix, iy), b = sample(ix + 1, iy)
        let c = sample(ix, iy + 1), d = sample(ix + 1, iy + 1)
        return dx + dy <= 1
            ? a + (b - a) * dx + (c - a) * dy
            : d + (c - d) * (1 - dx) + (b - d) * (1 - dy)
    }

    /// Fits a building to the local terrain plane instead of placing it
    /// vertically on the highest point below its footprint.
    func buildingPlacement(
        _ coordinate: CLLocationCoordinate2D,
        halfWidth: Float,
        halfDepth: Float,
        rotation: Float
    ) -> (surface: Float, orientation: simd_quatf) {
        let center = MKMapPoint(coordinate)
        let c = cos(rotation)
        let s = sin(rotation)

        func sample(_ localX: Float, _ localZ: Float) -> SIMD3<Float> {
            let east = (Double(localX) * Double(c) - Double(localZ) * Double(s)) / scale
            let north = (Double(localX) * Double(s) + Double(localZ) * Double(c)) / scale
            let mapPoint = MKMapPoint(x: center.x + east, y: center.y - north)
            var result = SIMD3<Float>(
                Float((mapPoint.x - origin.x) * scale),
                0,
                Float((mapPoint.y - origin.y) * scale)
            )
            result.y = renderedHeight(at: result)
            return result
        }

        let centerPoint = sample(0, 0)
        let localXAxis = sample(halfWidth, 0) - sample(-halfWidth, 0)
        let localZAxis = sample(0, halfDepth) - sample(0, -halfDepth)
        var normal = simd_normalize(simd_cross(localZAxis, localXAxis))
        if normal.y < 0 { normal = -normal }

        let yaw = simd_quatf(angle: rotation, axis: [0, 1, 0])
        let terrainTilt = simd_quatf(from: [0, 1, 0], to: normal)
        return (centerPoint.y, simd_mul(terrainTilt, yaw))
    }
    private func coordinate(_ localPoint: SIMD3<Float>) -> CLLocationCoordinate2D {
        MKMapPoint(
            x: origin.x + Double(localPoint.x) / scale,
            y: origin.y + Double(localPoint.z) / scale
        ).coordinate
    }
    private func isInsideRealityArea(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Bool {
        BaduyWorld.isInsideRealityArea(coordinate((a + b + c) / 3))
    }
    func entity(texture terrainTexture: TextureResource? = nil) throws -> Entity {
        var vertices: [SIMD3<Float>] = [], indices: [UInt32] = [], uv: [SIMD2<Float>] = []
        var contours: [SIMD3<Float>] = [], contourIndices: [UInt32] = []
        let samples = renderSamples.count
        for y in 0..<samples { for x in 0..<samples {
            let sourceX = Double(x) / Double(samples - 1) * 255
            let sourceY = Double(y) / Double(samples - 1) * 255
            let p = MKMapPoint(x: (3256 + (sourceX + 0.5)/256)*tileSize,
                               y: (2123 + (sourceY + 0.5)/256)*tileSize)
            vertices.append([Float((p.x-origin.x)*scale), height(p), Float((p.y-origin.y)*scale)])
            uv.append([Float(x) / Float(samples - 1), 1 - Float(y) / Float(samples - 1)])
        }}
        for y in 0..<(samples - 1) { for x in 0..<(samples - 1) {
            let a = UInt32(y*samples+x), b = a+1, c = a+UInt32(samples), d = c+1
            // Keep both halves of each cell together. Selecting them
            // independently creates long triangular teeth at the map edge.
            let cellCenter = (vertices[Int(a)] + vertices[Int(b)] + vertices[Int(c)] + vertices[Int(d)]) / 4
            // Keep the full DEM cell when its center is in the geographic
            // area. The smooth boundary surface overlaps these outer cells;
            // keeping them prevents gaps when the map is viewed obliquely.
            let cellIsInside = BaduyWorld.isInsideRealityArea(coordinate(cellCenter))
            if cellIsInside { indices += [a,c,b,b,c,d] }
            // Triangle intersections avoid ambiguous marching-squares saddle cases.
            for tri in [[a,c,b],[b,c,d]] {
                let v = tri.map { vertices[Int($0)] }
                guard cellIsInside else { continue }
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
        if let texture = terrainTexture {
            var material = UnlitMaterial(color: .white)
            material.color = .init(tint: .white, texture: .init(texture))
            result.addChild(ModelEntity(mesh: terrainMesh, materials: [material]))
        } else {
            result.addChild(ModelEntity(mesh: terrainMesh, materials: [UnlitMaterial(color: UIColor(red:0.25,green:0.43,blue:0.33,alpha:1))]))
        }
        // Replace the grid-shaped outer cells with a DEM-sampled boundary.
        // Its top uses the same texture and its skirt follows the same smooth
        // geographic line, eliminating the triangular teeth at the edge.
        try addSmoothTerrainBoundary(to: result, texture: terrainTexture)
        // Keep the contour overlay lightweight for Metal Simulator.
        if !contourIndices.isEmpty && contourIndices.count <= 12_000 {
            result.addChild(try Self.mesh(contours, contourIndices, color: UIColor(red:0.055,green:0.18,blue:0.25,alpha:0.64)))
        }
        try addRoads(to: result)
        return result
    }
    private func addSmoothTerrainBoundary(to parent: Entity, texture: TextureResource?) throws {
        let outline = BaduyWorld.realityArea
        guard outline.count >= 3 else { return }

        // Sample the rounded geographic outline at a fixed distance. The
        // resulting outer loop is independent from the square DEM grid.
        var outerCoordinates: [CLLocationCoordinate2D] = []
        for index in outline.indices {
            let a = outline[index]
            let b = outline[(index + 1) % outline.count]
            let length = simd_distance(
                SIMD2<Float>(point(a).x, point(a).z),
                SIMD2<Float>(point(b).x, point(b).z)
            )
            let steps = max(1, Int(ceil(length / 10)))
            for step in 0..<steps {
                outerCoordinates.append(Self.interpolate(a, b, t: Double(step) / Double(steps)))
            }
        }
        guard outerCoordinates.count >= 3 else { return }

        let outerPoints = outerCoordinates.map(point)
        let overlap: Float = 95
        var surfaceVertices: [SIMD3<Float>] = []
        var surfaceUVs: [SIMD2<Float>] = []
        var surfaceIndices: [UInt32] = []
        surfaceVertices.reserveCapacity(outerPoints.count * 2)
        surfaceUVs.reserveCapacity(outerPoints.count * 2)
        surfaceIndices.reserveCapacity(outerPoints.count * 12)

        func uv(for coordinate: CLLocationCoordinate2D) -> SIMD2<Float> {
            let mapPoint = MKMapPoint(coordinate)
            let sourceX = (mapPoint.x / tileSize - 3256) * 256 - 0.5
            let sourceY = (mapPoint.y / tileSize - 2123) * 256 - 0.5
            return [Float(sourceX / 255), 1 - Float(sourceY / 255)]
        }

        let crossSteps = 32
        let rowSize = crossSteps + 1
        for (index, outer) in outerPoints.enumerated() {
            // Move perpendicular to the edge, not toward the map's center.
            // In a long corridor the center direction runs almost parallel
            // to the edge, leaving a very narrow strip and an open seam.
            let previous = outerPoints[(index + outerPoints.count - 1) % outerPoints.count]
            let next = outerPoints[(index + 1) % outerPoints.count]
            let tangent = SIMD2<Float>(next.x - previous.x, next.z - previous.z)
            var direction = SIMD2<Float>(-tangent.y, tangent.x) / max(simd_length(tangent), 0.001)
            let probe = outer + SIMD3<Float>(direction.x * 2, 0, direction.y * 2)
            if !BaduyWorld.isInsideRealityArea(coordinate(probe)) { direction = -direction }
            let innerXZ = SIMD2<Float>(outer.x, outer.z) + direction * overlap
            for step in 0...crossSteps {
                let t = Float(step) / Float(crossSteps)
                let xz = SIMD2<Float>(outer.x, outer.z) * (1 - t) + innerXZ * t
                var vertex = SIMD3<Float>(xz.x, 0, xz.y)
                vertex.y = renderedHeight(at: vertex) + 0.08
                surfaceVertices.append(vertex)
                surfaceUVs.append(uv(for: coordinate(vertex)))
            }
        }

        for index in outerPoints.indices {
            let next = (index + 1) % outerPoints.count
            for step in 0..<crossSteps {
            let outerA = UInt32(index * rowSize + step)
            let innerA = outerA + 1
            let outerB = UInt32(next * rowSize + step)
            let innerB = outerB + 1
            surfaceIndices += [outerA, innerA, outerB, outerB, innerA, innerB]
            surfaceIndices += [outerB, innerA, outerA, innerB, innerA, outerB]
            }
        }

        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(surfaceVertices)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(surfaceUVs)
        descriptor.primitives = .triangles(surfaceIndices)
        let mesh = try MeshResource.generate(from: [descriptor])
        if let texture {
            var material = UnlitMaterial(color: .white)
            material.color = .init(tint: .white, texture: .init(texture))
            parent.addChild(ModelEntity(mesh: mesh, materials: [material]))
        } else {
            parent.addChild(ModelEntity(mesh: mesh, materials: [
                UnlitMaterial(color: UIColor(red: 0.25, green: 0.43, blue: 0.33, alpha: 1))
            ]))
        }

        let floorY = (outerPoints.map(\.y).min() ?? 0) - 18
        var skirtVertices: [SIMD3<Float>] = []
        var skirtIndices: [UInt32] = []
        skirtVertices.reserveCapacity(outerPoints.count * 2)
        skirtIndices.reserveCapacity(outerPoints.count * 12)
        for outer in outerPoints {
            skirtVertices += [outer, [outer.x, floorY, outer.z]]
        }
        for index in outerPoints.indices {
            let next = (index + 1) % outerPoints.count
            let topA = UInt32(index * 2)
            let bottomA = topA + 1
            let topB = UInt32(next * 2)
            let bottomB = topB + 1
            skirtIndices += [topA, bottomA, topB, topB, bottomA, bottomB]
            skirtIndices += [topB, bottomA, topA, bottomB, bottomA, topB]
        }
        parent.addChild(try Self.mesh(
            skirtVertices,
            skirtIndices,
            color: UIColor(red: 0.31, green: 0.25, blue: 0.16, alpha: 1)
        ))
    }

    private func addRoads(to parent: Entity) throws {
        guard let url = Bundle.main.url(forResource: "ciboleger", withExtension: "geojson") else { return }
        let collection = try JSONDecoder().decode(Collection.self, from: Data(contentsOf: url))
        var vertices: [SIMD3<Float>] = [], indices: [UInt32] = []

        for feature in collection.features where feature.properties.kind == "highway" {
            let coordinates = feature.geometry.coordinates.map {
                CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
            }
            guard coordinates.count > 1 else { continue }

            // Keep each OSM way as one continuous strip. Independent
            // quads per segment were the source of visible breaks and spikes.
            let width: Float = ["path", "footway", "track", "bridleway", "steps"]
                .contains(feature.properties.value) ? 3.4 : 5.2
            var centerline: [SIMD3<Float>] = []

            for index in 0..<(coordinates.count - 1) {
                let a = point(coordinates[index])
                let b = point(coordinates[index + 1])
                let length = simd_distance(
                    SIMD2<Float>(a.x, a.z),
                    SIMD2<Float>(b.x, b.z)
                )
                let steps = max(1, Int(ceil(length)))

                for step in 0..<steps {
                    let t = Double(step) / Double(steps)
                    let coordinate = Self.interpolate(
                        coordinates[index],
                        coordinates[index + 1],
                        t: t
                    )
                    guard BaduyWorld.isInsideRealityArea(coordinate, insetMeters: 4) else {
                        continue
                    }
                    let sample = point(coordinate)
                    if centerline.last.map({ simd_distance($0, sample) < 0.01 }) != true {
                        centerline.append(sample)
                    }
                }
            }

            if let lastCoordinate = coordinates.last,
               BaduyWorld.isInsideRealityArea(lastCoordinate, insetMeters: 4) {
                centerline.append(point(lastCoordinate))
            }

            terrainRoadStrip(
                centerline,
                width: width,
                clearance: 0.12,
                vertices: &vertices,
                indices: &indices
            )
        }

        if !indices.isEmpty {
            parent.addChild(try Self.mesh(
                vertices,
                indices,
                color: UIColor(red: 0.91, green: 0.82, blue: 0.62, alpha: 1)
            ))
        }
    }

    /// Creates stable short road segments that follow the terrain.
    /// Each segment overlaps its neighbor slightly, avoiding miter spikes at
    /// sharp OSM turns while keeping the road above the DEM.
    private func terrainRoadStrip(
        _ centerline: [SIMD3<Float>],
        width: Float,
        clearance: Float,
        vertices: inout [SIMD3<Float>],
        indices: inout [UInt32]
    ) {
        guard centerline.count >= 2 else { return }

        for index in 0..<(centerline.count - 1) {
            let start = centerline[index]
            let end = centerline[index + 1]
            let horizontal = SIMD3<Float>(end.x - start.x, 0, end.z - start.z)
            let length = simd_length(horizontal)
            guard length > 0.001, length < 16 else { continue }

            let direction = horizontal / length
            let side = SIMD3<Float>(-direction.z, 0, direction.x) * (width / 2)
            let overlap: Float = min(0.6, length * 0.15)
            let a = start - direction * overlap
            let b = end + direction * overlap
            let corners = [a - side, a + side, b - side, b + side]

            let segmentVertices = corners.map {
                SIMD3<Float>($0.x, renderedHeight(at: $0) + clearance, $0.z)
            }
            let offset = UInt32(vertices.count)
            vertices += segmentVertices
            indices += [
                offset, offset + 1, offset + 2,
                offset + 1, offset + 3, offset + 2
            ]
        }
    }

    private static func interpolate(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        t: Double
    ) -> CLLocationCoordinate2D {
        .init(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
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
