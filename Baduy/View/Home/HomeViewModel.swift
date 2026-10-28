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
        let proposed = CLLocationCoordinate2D(latitude: latitude,
            longitude: (longitude + 540).truncatingRemainder(dividingBy: 360) - 180)
        let snapped = snapToMappedTrail(proposed) ?? proposed
        updateLocation(CLLocation(coordinate: snapped,
            altitude: 0, horizontalAccuracy: 1, verticalAccuracy: 1, timestamp: .now))
    }

    /// Keeps debug/dead-reckoned movement on the real GeoJSON trail network.
    /// Projection is done in local metres, then converted back to coordinates.
    private func snapToMappedTrail(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D? {
        let latitudeScale = 111_320.0
        let longitudeScale = latitudeScale * cos(coordinate.latitude * .pi / 180)
        var best: (distance: Double, coordinate: CLLocationCoordinate2D)?
        for trail in trails where trail.count > 1 {
            for pair in zip(trail, trail.dropFirst()) {
                let a = pair.0, b = pair.1
                let ax = (a.longitude - coordinate.longitude) * longitudeScale
                let az = (a.latitude - coordinate.latitude) * latitudeScale
                let bx = (b.longitude - coordinate.longitude) * longitudeScale
                let bz = (b.latitude - coordinate.latitude) * latitudeScale
                let dx = bx - ax, dz = bz - az
                let denominator = dx * dx + dz * dz
                let t = denominator > 0 ? min(1, max(0, -(ax * dx + az * dz) / denominator)) : 0
                let x = ax + dx * t, z = az + dz * t
                let distance = hypot(x, z)
                guard distance <= 28 else { continue }
                let candidate = CLLocationCoordinate2D(
                    latitude: coordinate.latitude + z / latitudeScale,
                    longitude: coordinate.longitude + x / longitudeScale
                )
                if best == nil || distance < best!.distance {
                    best = (distance, candidate)
                }
            }
        }
        return best?.coordinate
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

    /// The closest village geofence currently containing the user.
    var currentGeofence: MapLandmark? {
        guard let location else { return nil }
        return landmarks
            .filter { landmark in
                let center = CLLocation(
                    latitude: landmark.coordinate.latitude,
                    longitude: landmark.coordinate.longitude
                )
                return location.distance(from: center) <= landmark.radius
            }
            .min { lhs, rhs in
                let lhsCenter = CLLocation(
                    latitude: lhs.coordinate.latitude,
                    longitude: lhs.coordinate.longitude
                )
                let rhsCenter = CLLocation(
                    latitude: rhs.coordinate.latitude,
                    longitude: rhs.coordinate.longitude
                )
                return location.distance(from: lhsCenter) < location.distance(from: rhsCenter)
            }
    }

    var selectedLandmark: MapLandmark?
    var enteredLandmark: MapLandmark?
    let landmarks: [MapLandmark]
    let trails: [[CLLocationCoordinate2D]]

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private let motionManager = CMMotionManager()
    @ObservationIgnored private var stepArmed = true
    @ObservationIgnored private var lastMotionStep: TimeInterval = 0
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
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = false
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

        // Detect gait peaks directly instead of waiting for batched pedometer
        // totals. Hysteresis and a refractory period reject repeated peaks.
        if motionManager.isDeviceMotionAvailable {
            stepArmed = true
            lastMotionStep = 0
            motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                guard let self, self.isWalkingSimulationActive, self.isActive else { return }
                guard let motion, error == nil else {
                    self.motionManager.stopDeviceMotionUpdates()
                    self.startPedometerFallback()
                    return
                }
                let acceleration = motion.userAcceleration
                let gravity = motion.gravity
                let vertical = -(acceleration.x * gravity.x + acceleration.y * gravity.y + acceleration.z * gravity.z)
                if vertical < 0.025 { self.stepArmed = true }
                guard self.stepArmed, vertical > 0.12,
                      motion.timestamp - self.lastMotionStep >= 0.32 else { return }
                self.stepArmed = false
                self.lastMotionStep = motion.timestamp
                let bearing = self.debugHeading * .pi / 180
                self.advanceDebugPlayer(east: sin(bearing) * 0.72, north: cos(bearing) * 0.72)
            }
            return
        }
        startPedometerFallback()
    }

    private func startPedometerFallback() {
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
        motionManager.stopDeviceMotionUpdates()
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
        status = isDebugMode ? "DEBUG · Berjalan mengikuti arah perangkat" : "GPS ±\(Int(location.horizontalAccuracy)) m"
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
