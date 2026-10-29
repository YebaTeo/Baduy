import CoreLocation

/// Product routing area inherited from Baduy's illustrative map boundary.
/// This is not an official administrative boundary. Replace with surveyed data when available.
enum MapAreaPolicy {
    static func isInside(_ location: CLLocation, now: Date = .now) -> Bool? {
        let age = now.timeIntervalSince(location.timestamp)
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 250,
              age >= -5, age <= 30 else { return nil }
        let boundary = MapLandmark.baduyRegion
        let p = location.coordinate
        var inside = false
        var edgeDistance = Double.infinity
        // Local metre projection is sufficient for this small routing area.
        let longitudeScale = 111_320 * cos(p.latitude * .pi / 180)
        for i in boundary.indices {
            let a = boundary[i], b = boundary[(i + 1) % boundary.count]
            if (a.latitude > p.latitude) != (b.latitude > p.latitude),
               p.longitude < (b.longitude - a.longitude) * (p.latitude - a.latitude)
                / (b.latitude - a.latitude) + a.longitude { inside.toggle() }
            let ax = (a.longitude - p.longitude) * longitudeScale
            let ay = (a.latitude - p.latitude) * 111_320
            let bx = (b.longitude - p.longitude) * longitudeScale
            let by = (b.latitude - p.latitude) * 111_320
            let dx = bx - ax, dy = by - ay
            let t = min(1, max(0, -(ax * dx + ay * dy) / max(1, dx * dx + dy * dy)))
            edgeDistance = min(edgeDistance, hypot(ax + t * dx, ay + t * dy))
        }
        // An accuracy circle crossing the boundary is inconclusive; keep the photo map.
        guard edgeDistance > max(20, location.horizontalAccuracy) else { return nil }
        return inside
    }
}
