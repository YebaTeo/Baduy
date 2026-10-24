import Foundation
import CoreLocation
import simd

/// Builds a performance-safe, geographically distributed set of houses from
/// every village-sector/road group present in `ciboleger.geojson`.
extension SettlementData {
    static let displayedBuildings: [SettlementBuilding] = {
        RepresentativeSettlementLoader.load(maximumCount: 214) ?? surroundingBuildings
    }()
}

private enum RepresentativeSettlementLoader {
    private struct Root: Decodable { let features: [Feature] }
    private struct Feature: Decodable {
        let properties: Properties
        let geometry: Geometry
    }
    private struct Properties: Decodable {
        let kind: String
        let value: String?
        let osm_id: String
    }
    private struct Geometry: Decodable {
        let type: String
        let coordinates: [[Double]]
    }
    private struct Road {
        let id: String
        let points: [SIMD2<Float>]
    }
    private struct Candidate {
        let building: SettlementBuilding
        let center: SIMD2<Float>
        let roadID: String
        let sectorX: Int
        let sectorZ: Int
    }
    private struct GroupKey: Hashable {
        let sectorX: Int
        let sectorZ: Int
        let roadID: String
    }

    /// A sector separates distant kampung clusters while the nearest OSM road
    /// preserves each local jalan group inside that cluster.
    private static let sectorSize: Float = 600

    static func load(maximumCount: Int) -> [SettlementBuilding]? {
        guard let url = Bundle.main.url(forResource: "ciboleger", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data) else { return nil }

        let roads = root.features.compactMap(makeRoad)
        guard !roads.isEmpty else { return nil }

        let candidates = root.features.compactMap { makeCandidate($0, roads: roads) }
        guard !candidates.isEmpty else { return nil }

        let groups = Dictionary(grouping: candidates) {
            GroupKey(sectorX: $0.sectorX, sectorZ: $0.sectorZ, roadID: $0.roadID)
        }
        let orderedGroups = groups.values.sorted {
            let a = $0.first!, b = $1.first!
            if a.sectorZ != b.sectorZ { return a.sectorZ < b.sectorZ }
            if a.sectorX != b.sectorX { return a.sectorX < b.sectorX }
            return a.roadID < b.roadID
        }

        // First retain one house from every village-sector/road group. Extra
        // slots go to the most populated groups, up to three representatives.
        var quota = Array(repeating: 1, count: orderedGroups.count)
        var remaining = max(0, maximumCount - orderedGroups.count)
        let priority = orderedGroups.indices.sorted {
            orderedGroups[$0].count > orderedGroups[$1].count
        }
        for desiredQuota in 2...3 where remaining > 0 {
            for index in priority where remaining > 0 && orderedGroups[index].count >= desiredQuota {
                quota[index] = desiredQuota
                remaining -= 1
            }
        }

        return orderedGroups.indices.flatMap { index in
            evenlySpread(orderedGroups[index], count: quota[index]).map(\.building)
        }
    }

    private static func makeRoad(_ feature: Feature) -> Road? {
        guard feature.properties.kind == "highway",
              feature.geometry.type == "LineString" else { return nil }
        let points = feature.geometry.coordinates.compactMap(localPoint)
        guard points.count >= 2 else { return nil }
        return Road(id: feature.properties.osm_id, points: points)
    }

    private static func makeCandidate(_ feature: Feature, roads: [Road]) -> Candidate? {
        guard feature.properties.kind == "building",
              feature.geometry.type == "LineString" else { return nil }
        var footprint = feature.geometry.coordinates.compactMap(localPoint)
        guard footprint.count >= 3 else { return nil }
        if footprint.first == footprint.last { footprint.removeLast() }
        guard !footprint.isEmpty else { return nil }

        let center = footprint.reduce(.zero, +) / Float(footprint.count)
        let nearestRoad = roads.min {
            squaredDistance(from: center, to: $0) < squaredDistance(from: center, to: $1)
        }!

        let axes = orientedBounds(footprint)
        let area = axes.width * axes.depth
        let kind: SettlementBuilding.BuildingKind
        if feature.properties.value == "mosque" || area > 105 {
            kind = .communityGazebo
        } else if area < 30 {
            kind = .granaryLeuit
        } else {
            kind = .residentialStiltHouse
        }
        let building = SettlementBuilding(
            id: "b_\(feature.properties.osm_id)",
            position: [center.x, 0, center.y],
            size: [max(4, axes.width), 3.2, max(4, axes.depth)],
            rotationY: axes.rotation,
            kind: kind
        )
        return Candidate(
            building: building,
            center: center,
            roadID: nearestRoad.id,
            sectorX: Int(floor(center.x / sectorSize)),
            sectorZ: Int(floor(center.y / sectorSize))
        )
    }

    private static func localPoint(_ coordinate: [Double]) -> SIMD2<Float>? {
        guard coordinate.count >= 2 else { return nil }
        let p = BaduyWorld.position(.init(latitude: coordinate[1], longitude: coordinate[0]))
        return [p.x, p.z]
    }

    private static func orientedBounds(_ points: [SIMD2<Float>]) -> (width: Float, depth: Float, rotation: Float) {
        var longest = SIMD2<Float>(1, 0)
        var longestSquared: Float = 0
        for index in points.indices {
            let edge = points[(index + 1) % points.count] - points[index]
            let lengthSquared = simd_length_squared(edge)
            if lengthSquared > longestSquared { longest = edge; longestSquared = lengthSquared }
        }
        let rotation = atan2(longest.y, longest.x)
        let xAxis = simd_normalize(longest)
        let zAxis = SIMD2<Float>(-xAxis.y, xAxis.x)
        let xValues = points.map { simd_dot($0, xAxis) }
        let zValues = points.map { simd_dot($0, zAxis) }
        return ((xValues.max() ?? 4) - (xValues.min() ?? 0),
                (zValues.max() ?? 4) - (zValues.min() ?? 0), rotation)
    }

    private static func squaredDistance(from point: SIMD2<Float>, to road: Road) -> Float {
        zip(road.points, road.points.dropFirst()).map { a, b in
            let segment = b - a
            let denominator = max(simd_length_squared(segment), 0.0001)
            let t = min(1, max(0, simd_dot(point - a, segment) / denominator))
            return simd_length_squared(point - (a + segment * t))
        }.min() ?? .greatestFiniteMagnitude
    }

    private static func evenlySpread(_ candidates: [Candidate], count: Int) -> [Candidate] {
        guard count > 0, candidates.count > count else { return candidates }
        // Farthest-point selection prevents representatives from accumulating
        // at one end of a long road or dense kampung block.
        var selected = [candidates.min { $0.center.x + $0.center.y < $1.center.x + $1.center.y }!]
        while selected.count < count {
            let next = candidates
                .filter { candidate in !selected.contains { $0.building.id == candidate.building.id } }
                .max { lhs, rhs in
                    nearestSelectedDistance(lhs, selected) < nearestSelectedDistance(rhs, selected)
                }
            guard let next else { break }
            selected.append(next)
        }
        return selected
    }

    private static func nearestSelectedDistance(_ candidate: Candidate, _ selected: [Candidate]) -> Float {
        selected.map { simd_length_squared(candidate.center - $0.center) }.min() ?? 0
    }
}
