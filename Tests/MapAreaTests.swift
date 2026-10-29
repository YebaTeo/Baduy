import Foundation
import CoreLocation

@main struct MapAreaTests {
    static func main() {
        let now = Date()
        var count = 0
        func check(_ name: String, latitude: Double, longitude: Double, accuracy: Double = 10,
                   age: Double = 0, expected: Bool?) {
            let location = CLLocation(coordinate: .init(latitude: latitude, longitude: longitude),
                                      altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 1,
                                      timestamp: now.addingTimeInterval(-age))
            let result = MapAreaPolicy.isInside(location, now: now)
            precondition(result == expected, "\(name): got \(String(describing: result))")
            count += 1
        }
        check("Ciboleger", latitude: -6.5944, longitude: 106.2255, expected: true)
        check("Kaduketug", latitude: -6.597582, longitude: 106.224333, expected: true)
        check("Gajeboh", latitude: -6.6075, longitude: 106.2226, expected: true)
        check("Southern Kanekes", latitude: -6.63201, longitude: 106.23055, expected: true)
        check("Jakarta", latitude: -6.2, longitude: 106.8, expected: false)
        check("Yogyakarta", latitude: -7.8, longitude: 110.36, expected: false)
        check("Outside west", latitude: -6.6, longitude: 106.16, expected: false)
        check("Boundary vertex", latitude: -6.566, longitude: 106.181, expected: nil)
        check("Poor fix", latitude: -6.5944, longitude: 106.2255, accuracy: 3000, expected: nil)
        check("Invalid accuracy", latitude: -6.5944, longitude: 106.2255, accuracy: -1, expected: nil)
        check("Stale fix", latitude: -6.5944, longitude: 106.2255, age: 90, expected: nil)
        check("Future fix", latitude: -6.5944, longitude: 106.2255, age: -90, expected: nil)
        check("Invalid coordinate", latitude: 100, longitude: 106.2255, expected: nil)
        check("Unknown boundary side", latitude: -6.5661, longitude: 106.1811, accuracy: 100, expected: nil)
        print("\(count) map routing checks passed")
    }
}
