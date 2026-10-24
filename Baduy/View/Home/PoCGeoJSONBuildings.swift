import Foundation
import CoreLocation
import RealityKit

/// Loads point features from a bundled GeoJSON file named `baduy_buildings.geojson`.
/// Coordinates follow GeoJSON order: [longitude, latitude].
struct GeoJSONBuildings {
    struct Collection: Decodable { let features: [Feature] }
    struct Feature: Decodable {
        let properties: Properties?
        let geometry: Geometry
    }
    struct Properties: Decodable {
        let name: String?
        let kind: String?
        let rotation: Float?
    }
    struct Geometry: Decodable { let type: String; let coordinates: [Double] }

    static func load(origin: CLLocationCoordinate2D = BaduyWorld.origin) -> [SettlementBuilding] {
        guard let url = Bundle.main.url(forResource: "baduy_buildings", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let collection = try? JSONDecoder().decode(Collection.self, from: data) else { return [] }
        let meter = 111_320.0
        return collection.features.enumerated().compactMap { index, feature in
            guard feature.geometry.type.lowercased() == "point", feature.geometry.coordinates.count >= 2 else { return nil }
            let longitude = feature.geometry.coordinates[0]
            let latitude = feature.geometry.coordinates[1]
            let x = Float((longitude - origin.longitude) * meter * cos(origin.latitude * .pi / 180))
            let z = Float((origin.latitude - latitude) * meter)
            let kind = (feature.properties?.kind ?? "residential").lowercased()
            let buildingKind: SettlementBuilding.BuildingKind = kind.contains("leuit") ? .granaryLeuit : kind.contains("saung") ? .communityGazebo : .residentialStiltHouse
            return SettlementBuilding(id: feature.properties?.name ?? "geojson-\(index)", position: [x, 0, z], size: [5, 3, 4], rotationY: feature.properties?.rotation ?? 0, kind: buildingKind)
        }
    }
}
