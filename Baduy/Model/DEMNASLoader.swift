import CoreLocation
import Foundation

/// Fetches a compact elevation grid from BIG DEMNAS and caches it for offline use.
@MainActor
final class DEMNASLoader {
    struct Grid: Codable, Sendable {
        let columns: Int
        let rows: Int
        let minimumLatitude: Double
        let maximumLatitude: Double
        let minimumLongitude: Double
        let maximumLongitude: Double
        let values: [Float]
        let baseElevation: Float
        let fetchedAt: Date

        func height(at coordinate: CLLocationCoordinate2D) -> Float? {
            guard coordinate.latitude >= minimumLatitude,
                  coordinate.latitude <= maximumLatitude,
                  coordinate.longitude >= minimumLongitude,
                  coordinate.longitude <= maximumLongitude,
                  columns > 1,
                  rows > 1 else {
                return nil
            }

            let x = (coordinate.longitude - minimumLongitude)
                / (maximumLongitude - minimumLongitude) * Double(columns - 1)
            let y = (coordinate.latitude - minimumLatitude)
                / (maximumLatitude - minimumLatitude) * Double(rows - 1)
            let x0 = min(columns - 2, max(0, Int(floor(x))))
            let y0 = min(rows - 2, max(0, Int(floor(y))))
            let dx = Float(x - Double(x0))
            let dy = Float(y - Double(y0))

            let a = values[y0 * columns + x0]
            let b = values[y0 * columns + x0 + 1]
            let c = values[(y0 + 1) * columns + x0]
            let d = values[(y0 + 1) * columns + x0 + 1]
            return a + (b - a) * dx + (c - a) * dy + (a - b - c + d) * dx * dy
        }
    }

    private struct SampleResponse: Decodable {
        let samples: [Sample]
    }

    private struct Sample: Decodable {
        let value: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self.value = value
            } else if let value = try? container.decode(String.self),
                      let number = Double(value) {
                self.value = number
            } else {
                self.value = .nan
            }
        }
    }

    private struct Point {
        let coordinate: CLLocationCoordinate2D
        let row: Int
        let column: Int
    }

    private let endpoint = URL(string:
        "https://geoservices.big.go.id/raster/rest/services/DEMNAS/DEM_Indonesia/ImageServer/getSamples"
    )!
    private let cacheName = "demnas-ciboleger-grid.json"
    private let cacheLifetime: TimeInterval = 60 * 60 * 24 * 30
    private let gridSize = 128
    private let requestBatchSize = 500

    func load(for region: [CLLocationCoordinate2D]) async throws -> Grid {
        let bounds = bounds(for: region)
        if let cached = loadCache(), cached.fetchedAt.addingTimeInterval(cacheLifetime) > .now,
           cached.minimumLatitude <= bounds.minimumLatitude,
           cached.maximumLatitude >= bounds.maximumLatitude,
           cached.minimumLongitude <= bounds.minimumLongitude,
           cached.maximumLongitude >= bounds.maximumLongitude {
            return cached
        }

        let points = makeGridPoints(bounds: bounds)
        var values = [Float](repeating: .nan, count: points.count)

        for start in stride(from: 0, to: points.count, by: requestBatchSize) {
            let end = min(start + requestBatchSize, points.count)
            let batch = Array(points[start..<end])
            let samples = try await fetchSamples(batch.map(\.coordinate))
            guard samples.count == batch.count else {
                throw DEMNSError.invalidSampleCount(expected: batch.count, actual: samples.count)
            }

            for index in batch.indices {
                values[start + index] = Float(samples[index].value)
            }
        }

        let grid = Grid(
            columns: gridSize,
            rows: gridSize,
            minimumLatitude: bounds.minimumLatitude,
            maximumLatitude: bounds.maximumLatitude,
            minimumLongitude: bounds.minimumLongitude,
            maximumLongitude: bounds.maximumLongitude,
            values: values,
            baseElevation: values.first(where: { !$0.isNaN }) ?? 0,
            fetchedAt: .now
        )
        saveCache(grid)
        return grid
    }

    private func fetchSamples(_ coordinates: [CLLocationCoordinate2D]) async throws -> [Sample] {
        let geometry = [
            "points": coordinates.map { [$0.longitude, $0.latitude] }
        ]
        let geometryData = try JSONSerialization.data(withJSONObject: geometry)
        let geometryString = String(decoding: geometryData, as: UTF8.self)

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "geometry", value: geometryString),
            URLQueryItem(name: "geometryType", value: "esriGeometryMultipoint"),
            URLQueryItem(name: "returnFirstValueOnly", value: "true"),
            URLQueryItem(name: "f", value: "json")
        ]
        guard let url = components.url else {
            throw DEMNSError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw DEMNSError.invalidResponse
        }
        return try JSONDecoder().decode(SampleResponse.self, from: data).samples
    }

    private func makeGridPoints(bounds: Bounds) -> [Point] {
        var points: [Point] = []
        points.reserveCapacity(gridSize * gridSize)

        for row in 0..<gridSize {
            let latitude = bounds.minimumLatitude
                + (bounds.maximumLatitude - bounds.minimumLatitude)
                * Double(row) / Double(gridSize - 1)
            for column in 0..<gridSize {
                let longitude = bounds.minimumLongitude
                    + (bounds.maximumLongitude - bounds.minimumLongitude)
                    * Double(column) / Double(gridSize - 1)
                points.append(Point(
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    row: row,
                    column: column
                ))
            }
        }
        return points
    }

    private struct Bounds {
        let minimumLatitude: Double
        let maximumLatitude: Double
        let minimumLongitude: Double
        let maximumLongitude: Double
    }

    private func bounds(for region: [CLLocationCoordinate2D]) -> Bounds {
        let padding = 0.001
        return Bounds(
            minimumLatitude: (region.map(\.latitude).min() ?? -6.642) - padding,
            maximumLatitude: (region.map(\.latitude).max() ?? -6.592) + padding,
            minimumLongitude: (region.map(\.longitude).min() ?? 106.217) - padding,
            maximumLongitude: (region.map(\.longitude).max() ?? 106.242) + padding
        )
    }

    private func cacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(cacheName)
    }

    private func loadCache() -> Grid? {
        guard let url = cacheURL(),
              let data = try? Data(contentsOf: url),
              let grid = try? JSONDecoder().decode(Grid.self, from: data) else {
            return nil
        }
        return grid
    }

    private func saveCache(_ grid: Grid) {
        guard let url = cacheURL(),
              let data = try? JSONEncoder().encode(grid) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}

private enum DEMNSError: Error {
    case invalidResponse
    case invalidSampleCount(expected: Int, actual: Int)
}
