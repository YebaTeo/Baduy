import CoreLocation
import CoreMotion
import Observation

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
    private var debugHeading: CLLocationDirection = 0
    private var debugStepCount = 0

    func setDebugMode(_ enabled: Bool) {
        guard enabled != isDebugMode else { return }
        locationManager.stopUpdatingLocation()
        stopWalkingSimulation()
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
        let magnitude = max(1, hypot(east, north))
        let distance = 8.0 * min(max(elapsed, 0), 0.1)
        advanceDebugPlayer(
            east: east / magnitude * distance,
            north: north / magnitude * distance
        )
    }

    private func advanceDebugPlayer(east: Double, north: Double) {
        guard isDebugMode, isActive, let location else { return }
        let latitude = min(85, max(-85, location.coordinate.latitude + north / 111_320))
        let longitude = location.coordinate.longitude + east
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
    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private var isWalkingSimulationActive = false
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
            startWalkingSimulation()
            status = "DEBUG · Berjalan mengikuti arah perangkat"
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

    private func startWalkingSimulation() {
        guard !isWalkingSimulationActive else { return }
        isWalkingSimulationActive = true
        debugStepCount = 0
        locationManager.headingFilter = 2
        locationManager.headingOrientation = .portrait
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }

        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: .now) { [weak self] data, _ in
            guard let data else { return }
            let stepCount = data.numberOfSteps.intValue
            Task { @MainActor [weak self] in
                guard let self, self.isWalkingSimulationActive, self.isActive else { return }
                let delta = stepCount - self.debugStepCount
                self.debugStepCount = stepCount
                guard delta > 0 else { return }

                let bearing = self.debugHeading * .pi / 180
                let distance = Double(delta) * 0.72
                self.advanceDebugPlayer(
                    east: sin(bearing) * distance,
                    north: cos(bearing) * distance
                )
            }
        }
    }

    private func stopWalkingSimulation() {
        guard isWalkingSimulationActive else { return }
        isWalkingSimulationActive = false
        pedometer.stopUpdates()
        locationManager.stopUpdatingHeading()
    }

    func stop() {
        isActive = false
        locationManager.stopUpdatingLocation()
        stopWalkingSimulation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isActive { start() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading >= 0
            ? newHeading.trueHeading
            : newHeading.magneticHeading
        if heading >= 0 {
            debugHeading = heading
        }
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
