import CoreLocation
import Observation
import simd

struct MapLandmark: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    var radius: CLLocationDistance = 25
    var modelName: String? = nil
    // Metres above the map origin's vertical datum, not GPS altitude.
    var elevation: Float = 0
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
}

/// A small-area projection: metres, +X east, +Y up, -Z north.
/// Keep this origin fixed and match it to the terrain's surveyed origin later.
struct MapOrigin {
    let coordinate: CLLocationCoordinate2D

    func position(for coordinate: CLLocationCoordinate2D, elevation: Float = 0) -> SIMD3<Float> {
        let radians = Double.pi / 180
        let earthRadius = 6_378_137.0
        let longitudeDelta = (coordinate.longitude - self.coordinate.longitude + 540)
            .truncatingRemainder(dividingBy: 360) - 180
        let east = longitudeDelta * radians * earthRadius * cos(self.coordinate.latitude * radians)
        let north = (coordinate.latitude - self.coordinate.latitude) * radians * earthRadius
        return SIMD3(Float(east), elevation, Float(-north))
    }
}

@MainActor
@Observable
final class HomeViewModel: NSObject, CLLocationManagerDelegate {
    private(set) var origin: MapOrigin?
    private(set) var location: CLLocation?
    private(set) var playerPosition: SIMD3<Float>?
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

    init(origin: MapOrigin? = nil, landmarks: [MapLandmark] = [],
         trails: [[CLLocationCoordinate2D]] = []) {
        self.origin = origin ?? landmarks.first.map { MapOrigin(coordinate: $0.coordinate) }
        self.landmarks = landmarks
        self.trails = trails
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
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            status = "Waiting for location…"
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            location = nil
            playerPosition = nil
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
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 50,
              abs(location.timestamp.timeIntervalSinceNow) < 15 else { return }
        // With no surveyed map supplied, anchor this session at the first GPS fix.
        if origin == nil { origin = MapOrigin(coordinate: location.coordinate) }
        self.location = location
        playerPosition = origin?.position(for: location.coordinate)
        status = "GPS ±\(Int(location.horizontalAccuracy)) m"
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
        status = "Location unavailable: \(error.localizedDescription)"
    }
}
