import Foundation
import CoreLocation
import RealityKit
import UIKit

/// Real geographic origin: Pusat Wilayah Adat Ciboleger - Kanekes (-6.601760, 106.222022)
enum BaduyWorld {
    // Optimal geographic center encompassing all landmarks & 214 settlement buildings
    static let origin = CLLocationCoordinate2D(latitude: -6.601760, longitude: 106.222022)
    static let metersPerDegree = 111_320.0

    /// 3D exploration corridor from Terminal Ciboleger toward the Baduy villages.
    static let realityArea: [CLLocationCoordinate2D] = [
        // Northern buffer keeps the complete terminal area on the DEM even
        // after the entity safety inset is applied.
        .init(latitude: -6.59265, longitude: 106.22285),
        .init(latitude: -6.59265, longitude: 106.22780),
        .init(latitude: -6.60080, longitude: 106.22720),
        // Continue beyond Spot 5 so it sits inside the map rather than on its edge.
        .init(latitude: -6.63000, longitude: 106.24200),
        .init(latitude: -6.64200, longitude: 106.24200),
        .init(latitude: -6.64200, longitude: 106.23200),
        .init(latitude: -6.63000, longitude: 106.21700),
        .init(latitude: -6.61520, longitude: 106.21700),
        .init(latitude: -6.60220, longitude: 106.22050)
    ]

    static func isInsideRealityArea(_ coordinate: CLLocationCoordinate2D, insetMeters: Double = 0) -> Bool {
        var inside = false
        var previous = realityArea.count - 1
        for current in realityArea.indices {
            let a = realityArea[current], b = realityArea[previous]
            if (a.latitude > coordinate.latitude) != (b.latitude > coordinate.latitude) {
                let longitude = (b.longitude - a.longitude) *
                    (coordinate.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                if coordinate.longitude < longitude { inside.toggle() }
            }
            previous = current
        }
        guard inside, insetMeters > 0 else { return inside }

        // The DEM render grid is coarser than the source coordinates. Keep
        // entities away from polygon edges so they cannot land on a triangle
        // removed by terrain clipping.
        let latitudeScale = metersPerDegree
        let longitudeScale = metersPerDegree * cos(coordinate.latitude * .pi / 180)
        func local(_ point: CLLocationCoordinate2D) -> SIMD2<Double> {
            [(point.longitude - coordinate.longitude) * longitudeScale,
             (point.latitude - coordinate.latitude) * latitudeScale]
        }
        let point = SIMD2<Double>.zero
        var minimumDistance = Double.greatestFiniteMagnitude
        previous = realityArea.count - 1
        for current in realityArea.indices {
            let a = local(realityArea[previous])
            let b = local(realityArea[current])
            let segment = b - a
            let denominator = max(simd_length_squared(segment), 0.0001)
            let t = min(1, max(0, simd_dot(point - a, segment) / denominator))
            minimumDistance = min(minimumDistance, simd_length(point - (a + segment * t)))
            previous = current
        }
        return minimumDistance >= insetMeters
    }

    // Local map coordinates: x = east, z = south, y = up. One unit = one meter.
    static func position(_ coordinate: CLLocationCoordinate2D) -> SIMD3<Float> {
        SIMD3(Float((coordinate.longitude - origin.longitude) * metersPerDegree * cos(origin.latitude * .pi / 180)), 0,
              Float((origin.latitude - coordinate.latitude) * metersPerDegree))
    }

    static func coordinate(_ position: SIMD3<Float>) -> CLLocationCoordinate2D {
        .init(latitude: origin.latitude - Double(position.z) / metersPerDegree,
              longitude: origin.longitude + Double(position.x) / (metersPerDegree * cos(origin.latitude * .pi / 180)))
    }

    /// Elevation profile matching Ciboleger ridge -> Ciujung river valley -> Kaduketug foothills -> Kadujangkung slope across the full 2km territory
    static func height(_ x: Float, _ z: Float) -> Float {
        let ridge = 18.0 * cos(x / 420.0) * sin(z / 650.0)
        let valleyCut = -9.0 * exp(-((x - 10.0) * (x - 10.0)) / 9500.0) // Ciujung river valley
        let hillKaduketug = 22.0 * exp(-((x - 220.0) * (x - 220.0) + (z - 280.0) * (z - 280.0)) / 45000.0)
        let northernPlateau = 12.0 * max(0, (-z - 200.0) / 400.0)
        return max(1.0, 10.0 + ridge + valleyCut + hillKaduketug + northernPlateau)
    }

    static func usable(_ fix: CLLocation, now: Date) -> Bool {
        let age = now.timeIntervalSince(fix.timestamp)
        return age >= -5 && age <= 120 && fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= 100
    }

    static func nearby(_ landmark: BaduyLandmark, fix: CLLocation, now: Date) -> Bool {
        usable(fix, now: now) && fix.distance(from: CLLocation(latitude: landmark.coordinate.latitude, longitude: landmark.coordinate.longitude)) + fix.horizontalAccuracy <= 80
    }
}

struct BaduyLandmark: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let position: SIMD3<Float>
    let story: String
    let category: String
    var coordinate: CLLocationCoordinate2D { BaduyWorld.coordinate(position) }

    /// Loads landmarks directly from baduy_landmarks.geojson with fallback to static points
    static var samples: [BaduyLandmark] {
        if let landmarks = GeoJSONLandmarkLoader.loadFromBundle() {
            return landmarks
        }
        return defaultSamples
    }

    static let defaultSamples: [BaduyLandmark] = [
        .init(id: "tugu_ciboleger", title: "Tugu Patung Ciboleger", subtitle: "01 / Gerbang Wilayah Adat", position: [40, 0, -180], story: "Monumen ikonik patung warga Baduy dengan pakaian khas hitam-putih dan tas koja.", category: "monument"),
        .init(id: "terminal_ciboleger", title: "Terminal Ciboleger", subtitle: "02 / Titik Akhir Kendaraan", position: [42, 0, -170], story: "Terminal transportasi dan titik temu kendaraan bermotor terakhir.", category: "gateway"),
        .init(id: "kaduketug_center", title: "Kampung Adat Kaduketuk", subtitle: "03 / Sentra Tenun Baduy Luar", position: [85, 0, -80], story: "Kampung pertama Baduy Luar. Sentra kerajinan kain tenun motif aros dan tas koja.", category: "village"),
        .init(id: "jembatan_gajeboh", title: "Jembatan Bambu Ciujung", subtitle: "04 / Titian Tradisional", position: [-15, 0, 75], story: "Jembatan bambu gantung tradisional yang melintasi aliran deras Sungai Ciujung.", category: "bridge"),
        .init(id: "gardu_pandang", title: "Spot Panorama Perbukitan", subtitle: "05 / Gardu Pandang Lembah Adat", position: [-50, 0, 140], story: "Titik ketinggian bukit dengan pemandangan terbuka menghadap bentang alam lembah Kanekes.", category: "viewpoint")
    ]
}

/// Automatically decodes points of interest from GeoJSON into local 3D RealityKit coordinates
enum GeoJSONLandmarkLoader {
    struct GeoJSONRoot: Decodable {
        let features: [Feature]
    }
    struct Feature: Decodable {
        let properties: Properties
        let geometry: Geometry
    }
    struct Properties: Decodable {
        let id: String
        let title: String
        let subtitle: String
        let category: String?
        let story: String
    }
    struct Geometry: Decodable {
        let type: String
        let coordinates: [Double] // [lon, lat]
    }

    static func loadFromBundle() -> [BaduyLandmark]? {
        guard let url = Bundle.main.url(forResource: "baduy_landmarks", withExtension: "geojson") ??
                        Bundle.main.url(forResource: "baduy_landmarks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(GeoJSONRoot.self, from: data) else {
            // Check direct workspace path during debugging
            let localPath = "/Users/muhammadaliefrahmanfardillah/Swift Learn/PoC-C67/PoC-C67/baduy_landmarks.geojson"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: localPath)),
               let root = try? JSONDecoder().decode(GeoJSONRoot.self, from: data) {
                return parseFeatures(root.features)
            }
            return nil
        }
        return parseFeatures(root.features)
    }

    private static func parseFeatures(_ features: [Feature]) -> [BaduyLandmark] {
        return features.compactMap { f in
            guard f.geometry.coordinates.count >= 2 else { return nil }
            let lon = f.geometry.coordinates[0]
            let lat = f.geometry.coordinates[1]
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let localPos = BaduyWorld.position(coord)

            return BaduyLandmark(
                id: f.properties.id,
                title: f.properties.title,
                subtitle: f.properties.subtitle,
                position: localPos,
                story: f.properties.story,
                category: f.properties.category ?? "landmark"
            )
        }
    }
}

/// 3D Heritage and POI models based on GeoJSON category
enum HeritageModel {
    static func make(_ landmark: BaduyLandmark) -> ModelEntity {
        let root = ModelEntity()
        func box(_ size: SIMD3<Float>, _ position: SIMD3<Float>, _ color: UIColor) {
            let entity = ModelEntity(mesh: .generateBox(size: size), materials: [SimpleMaterial(color: color, roughness: 0.9, isMetallic: false)])
            entity.position = position
            root.addChild(entity)
        }
        let wood = UIColor(red: 0.52, green: 0.34, blue: 0.18, alpha: 1)
        box([0.8, 0.025, 0.65], [0, 0.0125, 0], .systemGreen)

        switch landmark.category {
        case "bridge":
            box([0.25, 0.008, 0.62], [0, 0.03, 0], .systemTeal)
            for i in 0..<12 { box([0.05, 0.025, 0.24], [Float(i) * 0.055 - 0.30, 0.13, 0], wood) }
            for z: Float in [-0.13, 0.13] {
                box([0.68, 0.015, 0.015], [0, 0.25, z], wood)
                for x: Float in [-0.3, 0, 0.3] { box([0.015, 0.22, 0.015], [x, 0.14, z], wood) }
            }

        case "monument":
            // Stone pedestal with cultural monument statue
            box([0.35, 0.15, 0.35], [0, 0.075, 0], .darkGray)
            box([0.22, 0.38, 0.22], [0, 0.34, 0], .white)
            box([0.16, 0.12, 0.16], [0, 0.58, 0], .black) // Ikat kepala lombar Baduy

        case "viewpoint":
            // Raised observation deck / wooden lookout tower
            for x: Float in [-0.20, 0.20] {
                for z: Float in [-0.20, 0.20] { box([0.03, 0.55, 0.03], [x, 0.275, z], wood) }
            }
            box([0.50, 0.03, 0.50], [0, 0.56, 0], wood)
            box([0.52, 0.10, 0.02], [0, 0.62, 0.24], wood)

        case "gateway":
            // Terminal gate arch
            for x: Float in [-0.28, 0.28] { box([0.05, 0.32, 0.05], [x, 0.16, 0], .systemBlue) }
            box([0.68, 0.06, 0.08], [0, 0.34, 0], .systemBlue)
            box([0.48, 0.03, 0.38], [0, 0.06, 0], .systemOrange)

        default:
            // Traditional Baduy Stilt House (Rumah Adat / Village)
            for x: Float in [-0.16, 0.16] {
                for z: Float in [-0.13, 0.13] { box([0.025, 0.18, 0.025], [x, 0.11, z], wood) }
            }
            box([0.38, 0.22, 0.32], [0, 0.27, 0], .init(red: 0.76, green: 0.61, blue: 0.37, alpha: 1))
            for sign: Float in [-1, 1] {
                let roof = ModelEntity(mesh: .generateBox(size: [0.27, 0.025, 0.42]), materials: [SimpleMaterial(color: wood, isMetallic: false)])
                roof.position = [sign * 0.10, 0.43, 0]
                roof.orientation = simd_quatf(angle: -sign * .pi / 5, axis: [0, 0, 1])
                root.addChild(roof)
            }
            for x: Float in [-0.24, 0, 0.24] { box([0.10, 0.06, 0.08], [x, 0.055, 0.24], .systemYellow) }
        }

        root.components.set(CollisionComponent(shapes: [.generateBox(size: [0.8, 0.6, 0.65]).offsetBy(translation: [0, 0.3, 0])]))
        root.components.set(InputTargetComponent())
        return root
    }
}
