import SwiftUI
import CoreLocation
import Combine

@MainActor final class MapDestinationState: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    enum Destination { case checking, baduy, photos }
    @Published private(set) var destination: Destination = .checking
    @Published private(set) var notice: String?
    #if DEBUG
    enum DebugLocation: String, CaseIterable, Identifiable {
        case automatic = "Use real GPS"
        case inside = "In Baduy"
        case outside = "Outside Baduy"
        var id: Self { self }
    }
    @Published var debugLocation: DebugLocation = .automatic
    #endif
    private let manager = CLLocationManager()
    private var timeout: Task<Void, Never>?
    private var active = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func check() {
        stop()
        #if DEBUG
        if debugLocation != .automatic {
            notice = nil
            destination = debugLocation == .inside ? .baduy : .photos
            return
        }
        #endif
        active = true
        destination = .checking
        notice = nil
        authorizeOrLocate()
    }
    func stop() {
        active = false
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
    }
    private func authorizeOrLocate() {
        guard active else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard timeout == nil else { return }
            manager.startUpdatingLocation()
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(12)) } catch { return }
                guard let self, self.active else { return }
                self.showPhotos("Location could not be confirmed. Showing the photo map.")
            }
        case .denied, .restricted:
            showPhotos("Location access is off. You can still explore the photo map.")
        @unknown default: showPhotos("Location is unavailable. Showing the photo map.")
        }
    }
    private func showPhotos(_ message: String?) {
        stop()
        notice = message
        destination = .photos
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizeOrLocate()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard active else { return }
        for location in locations.reversed() {
            guard let inside = MapAreaPolicy.isInside(location) else { continue }
            stop()
            destination = inside ? .baduy : .photos
            return
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard active else { return }
        if (error as? CLError)?.code == .locationUnknown { return }
        showPhotos("Location is unavailable. Showing the photo map.")
    }
}

struct LocationRoutedMapView: View {
    @ObservedObject var app: AppState
    let isActive: Bool
    @StateObject private var routing = MapDestinationState()
    @Environment(\.scenePhase) private var scenePhase
    private var shouldCheck: Bool { isActive && scenePhase == .active }

    var body: some View {
        Group {
            if !shouldCheck {
                Color.clear
            } else {
                switch routing.destination {
                case .checking:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Finding the right map for your location…")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding()
                case .baduy:
                    #if DEBUG
                    BaduyExperienceView(simulateLocation: routing.debugLocation == .inside)
                        .id(routing.debugLocation)
                    #else
                    BaduyExperienceView()
                    #endif
                case .photos:
                    ExploreMapView(app: app)
                        .safeAreaInset(edge: .bottom) {
                            if let notice = routing.notice {
                                HStack {
                                    Text(notice).font(.caption)
                                    Spacer()
                                    Button("Retry") { routing.check() }
                                }.padding(12).background(.regularMaterial)
                            }
                        }
                }
            }
        }
        #if DEBUG
        .safeAreaInset(edge: .top, spacing: 0) {
            if shouldCheck {
                HStack {
                    Label("Location test", systemImage: "ladybug.fill")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Menu {
                        Picker("Test location", selection: $routing.debugLocation) {
                            ForEach(MapDestinationState.DebugLocation.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    } label: {
                        HStack {
                            Text(routing.debugLocation.rawValue)
                            Image(systemName: "chevron.up.chevron.down")
                        }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }
                    .accessibilityLabel("Test location: \(routing.debugLocation.rawValue)")
                }
                .padding(.horizontal, 16)
                .background(.regularMaterial)
            }
        }
        .onChange(of: routing.debugLocation) { _, _ in
            if shouldCheck { routing.check() }
        }
        #endif
        .onChange(of: shouldCheck, initial: true) { _, active in
            if active { routing.check() } else { routing.stop() }
        }
        .onDisappear { routing.stop() }
    }
}
