import CoreLocation

struct MapLandmark: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    var radius: CLLocationDistance = 25
    var detail: String = ""
    var sourceURL: String? = nil

    // Published location references, not surveyed entrance/terrain coordinates.
    // Keep radii configurable until on-site coordinates are available.
    static let baduyPoints: [MapLandmark] = [
        MapLandmark(
            id: "ciboleger", name: "Ciboleger",
            coordinate: .init(latitude: -6.5944, longitude: 106.2255), radius: 75,
            detail: "Gateway settlement for entering the Baduy area.",
            sourceURL: "https://www.fallingrain.com/world/ID/33/Ciboleger.html"
        ),
        MapLandmark(
            id: "kaduketug", name: "Kaduketug",
            coordinate: .init(latitude: -6.597582, longitude: 106.224333), radius: 75,
            detail: "An Outer Baduy village near the Ciboleger entrance.",
            sourceURL: "https://doi.org/10.29244/jli.v17i2.61581"
        ),
        MapLandmark(
            id: "gajeboh", name: "Gajeboh",
            coordinate: .init(latitude: -6.6075, longitude: 106.2226), radius: 100,
            detail: "An Outer Baduy village south of Ciboleger.",
            sourceURL: "https://www.fallingrain.com/world/ID/33/Gajeboh.html"
        )
    ]

    /// Illustrative cartographic boundaries for the Baduy map skin.
    /// These are visual regions, not cadastral or administrative boundaries.
    static let baduyRegion: [CLLocationCoordinate2D] = [
        .init(latitude: -6.566, longitude: 106.181),
        .init(latitude: -6.558, longitude: 106.210),
        .init(latitude: -6.569, longitude: 106.251),
        .init(latitude: -6.603, longitude: 106.267),
        .init(latitude: -6.637, longitude: 106.247),
        .init(latitude: -6.655, longitude: 106.215),
        .init(latitude: -6.634, longitude: 106.184),
        .init(latitude: -6.600, longitude: 106.172)
    ]

    static let baduyForestRegions: [[CLLocationCoordinate2D]] = [
        [
            .init(latitude: -6.580, longitude: 106.190), .init(latitude: -6.572, longitude: 106.214),
            .init(latitude: -6.590, longitude: 106.229), .init(latitude: -6.611, longitude: 106.218),
            .init(latitude: -6.602, longitude: 106.190)
        ],
        [
            .init(latitude: -6.608, longitude: 106.230), .init(latitude: -6.592, longitude: 106.251),
            .init(latitude: -6.626, longitude: 106.253), .init(latitude: -6.641, longitude: 106.227),
            .init(latitude: -6.629, longitude: 106.208)
        ]
    ]

    static let baduyTrails: [[CLLocationCoordinate2D]] = [
        [
            .init(latitude: -6.5944, longitude: 106.2255),
            .init(latitude: -6.602, longitude: 106.222),
            .init(latitude: -6.6075, longitude: 106.2226),
            .init(latitude: -6.621, longitude: 106.216),
            .init(latitude: -6.641, longitude: 106.213)
        ],
        [
            .init(latitude: -6.585, longitude: 106.203),
            .init(latitude: -6.597582, longitude: 106.224333),
            .init(latitude: -6.615, longitude: 106.239),
            .init(latitude: -6.637, longitude: 106.247)
        ]
    ]

    static let baduyRivers: [[CLLocationCoordinate2D]] = [
        [
            .init(latitude: -6.568, longitude: 106.199), .init(latitude: -6.584, longitude: 106.205),
            .init(latitude: -6.603, longitude: 106.214), .init(latitude: -6.626, longitude: 106.221),
            .init(latitude: -6.651, longitude: 106.232)
        ],
        [
            .init(latitude: -6.574, longitude: 106.246), .init(latitude: -6.591, longitude: 106.240),
            .init(latitude: -6.610, longitude: 106.241), .init(latitude: -6.632, longitude: 106.251)
        ]
    ]
}
