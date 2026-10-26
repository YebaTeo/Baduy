import CoreLocation
import Observation

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
        ),
        MapLandmark(
            id: "baduy_dalam", name: "Baduy Dalam",
            coordinate: .init(latitude: -6.63742, longitude: 106.23858), radius: 180,
            detail: "Penanda koridor menuju kawasan Baduy Dalam di sekitar Cibeo.",
            sourceURL: "https://www.openstreetmap.org/?mlat=-6.63742&mlon=106.23858#map=15/-6.63742/106.23858"
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

@MainActor
@Observable
final class HomeViewModel: NSObject, CLLocationManagerDelegate {
    /// Characters stay at their spawn point while the user walks towards them.
    private(set) var encounterOrigin: CLLocationCoordinate2D?
    private(set) var location: CLLocation?
    #if DEBUG
    private(set) var isDebugMode = true
    #else
    private(set) var isDebugMode = false
    #endif
    private var debugStart: CLLocationCoordinate2D?

    func setDebugMode(_ enabled: Bool) {
        guard enabled != isDebugMode else { return }
        locationManager.stopUpdatingLocation()
        isDebugMode = enabled
        encounterOrigin = nil
        insideLandmarks.removeAll()
        enteredLandmark = nil
        if enabled {
            debugStart = location?.coordinate
            resetDebugPosition()
        } else {
            location = nil
            debugStart = nil
        }
        start()
    }

    func resetDebugPosition() {
        guard isDebugMode else { return }
        encounterOrigin = nil
        insideLandmarks.removeAll()
        enteredLandmark = nil
        let coordinate = debugStart ?? CLLocationCoordinate2D(latitude: -6.5952, longitude: 106.2255)
        updateLocation(CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 1,
                                  verticalAccuracy: 1, timestamp: .now))
    }

    /// North-up movement, metres per second; diagonals have the same maximum speed.
    func moveDebugPlayer(east: Double, north: Double, elapsed: TimeInterval) {
        guard isDebugMode, isActive, let location else { return }
        let magnitude = max(1, hypot(east, north))
        let step = 8.0 * min(max(elapsed, 0), 0.1)
        let latitude = min(85, max(-85, location.coordinate.latitude + north / magnitude * step / 111_320))
        let longitude = location.coordinate.longitude + east / magnitude * step
            / (111_320 * cos(latitude * .pi / 180))
        updateLocation(CLLocation(coordinate: .init(latitude: latitude,
            longitude: (longitude + 540).truncatingRemainder(dividingBy: 360) - 180),
            altitude: 0, horizontalAccuracy: 1, verticalAccuracy: 1, timestamp: .now))
    }

    let interactionRadius: CLLocationDistance = 20

    func coordinate(for character: BaduyCharacter) -> CLLocationCoordinate2D? {
        guard location != nil else { return nil }
        if isAtCiboleger == true { return character.coordinate }
        guard let origin = encounterOrigin else { return nil }
        let bearing = (character == .cowo ? 45.0 : 225.0) * .pi / 180
        let angularDistance = 40.0 / 6_371_000
        let latitude = origin.latitude * .pi / 180
        let longitude = origin.longitude * .pi / 180
        let targetLatitude = asin(sin(latitude) * cos(angularDistance)
            + cos(latitude) * sin(angularDistance) * cos(bearing))
        let targetLongitude = longitude + atan2(sin(bearing) * sin(angularDistance) * cos(latitude),
            cos(angularDistance) - sin(latitude) * sin(targetLatitude))
        return .init(latitude: targetLatitude * 180 / .pi,
                     longitude: (targetLongitude * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    func distance(to character: BaduyCharacter) -> CLLocationDistance? {
        guard let coordinate = coordinate(for: character) else { return nil }
        return location?.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    func canInteract(with character: BaduyCharacter, at date: Date = .now) -> Bool {
        guard isActive, let location, location.horizontalAccuracy <= interactionRadius,
              (isDebugMode || abs(location.timestamp.timeIntervalSince(date)) < 15),
              let distance = distance(to: character) else { return false }
        return distance <= interactionRadius
    }

    private(set) var status = "Waiting for location…"
    /// nil means no usable GPS fix; use the existing Ciboleger POI radius.
    var isAtCiboleger: Bool? {
        guard let location else { return nil }
        let gateway = landmarks.first { $0.id == "ciboleger" } ?? MapLandmark.baduyPoints[0]
        let center = CLLocation(latitude: gateway.coordinate.latitude,
                                longitude: gateway.coordinate.longitude)
        return location.distance(from: center) <= gateway.radius
    }

    var selectedLandmark: MapLandmark?
    var enteredLandmark: MapLandmark?
    let landmarks: [MapLandmark]
    let trails: [[CLLocationCoordinate2D]]

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var insideLandmarks: Set<String> = []
    @ObservationIgnored private var isActive = false
    /// Called once on entry; leaving the radius rearms the event.
    @ObservationIgnored var onLandmarkEntered: ((MapLandmark) -> Void)?

    init(landmarks: [MapLandmark] = [],
         trails: [[CLLocationCoordinate2D]] = []) {
        self.landmarks = landmarks
        self.trails = trails.isEmpty ? MapLandmark.baduyTrails : trails
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 2
    }

    func distance(to landmark: MapLandmark) -> CLLocationDistance? {
        location?.distance(from: CLLocation(latitude: landmark.coordinate.latitude,
                                            longitude: landmark.coordinate.longitude))
    }

    func start() {
        isActive = true
        if isDebugMode {
            if location == nil { resetDebugPosition() }
            status = "DEBUG · Gerakkan analog untuk berjalan"
            return
        }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            status = "Waiting for location…"
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            location = nil
            status = "Location unavailable. Allow location access in Settings."
        @unknown default:
            status = "Location unavailable."
        }
    }

    func stop() {
        isActive = false
        locationManager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isActive { start() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !isDebugMode, isActive, let location = locations.last,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 50,
              abs(location.timestamp.timeIntervalSinceNow) < 15 else { return }
        updateLocation(location)
    }

    private func updateLocation(_ location: CLLocation) {
        self.location = location
        if isAtCiboleger == false, encounterOrigin == nil, location.horizontalAccuracy <= interactionRadius {
            encounterOrigin = location.coordinate
        }
        status = isDebugMode ? "DEBUG · Gerakkan analog untuk berjalan" : "GPS ±\(Int(location.horizontalAccuracy)) m"
        for landmark in landmarks {
            let center = CLLocation(latitude: landmark.coordinate.latitude,
                                    longitude: landmark.coordinate.longitude)
            let isInside = location.distance(from: center) <= max(0, landmark.radius)
            if isInside {
                if insideLandmarks.insert(landmark.id).inserted {
                    enteredLandmark = landmark
                    onLandmarkEntered?(landmark)
                }
            } else {
                insideLandmarks.remove(landmark.id)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !isDebugMode else { return }
        status = "Location unavailable: \(error.localizedDescription)"
    }
}
