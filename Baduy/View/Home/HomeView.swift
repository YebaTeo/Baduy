import SwiftUI
import MapKit
import Combine

private enum MapPalette {
    static let ink = Color(red: 0.10, green: 0.22, blue: 0.31)
    static let paper = LinearGradient(
        colors: [Color(red: 1.0, green: 0.98, blue: 0.93), Color(red: 0.88, green: 0.93, blue: 0.87)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let indigo = LinearGradient(
        colors: [Color(red: 0.20, green: 0.36, blue: 0.49), Color(red: 0.10, green: 0.22, blue: 0.36)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let forest = LinearGradient(
        colors: [Color(red: 0.27, green: 0.44, blue: 0.34), Color(red: 0.16, green: 0.32, blue: 0.26)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let clay = LinearGradient(
        colors: [Color(red: 0.58, green: 0.37, blue: 0.25), Color(red: 0.43, green: 0.26, blue: 0.19)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct HomeView: View {
    @State private var model: HomeViewModel
    @State private var position: MapCameraPosition
    @State private var joystick = CGSize.zero
    @State private var lastMovementTick = Date.now
    @State private var didFocusUser = false
    @State private var interactionDate = Date.now
    @State private var selectedCharacter: BaduyCharacter?
    @State private var arCharacter: BaduyCharacter?
    @State private var cameraMode: BaduyCameraMode = .topDown
    @Environment(\.scenePhase) private var scenePhase

    init(model: HomeViewModel? = nil) {
        let model = model ?? HomeViewModel(landmarks: MapLandmark.baduyPoints)
        _model = State(initialValue: model)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: model.landmarks.first?.coordinate ?? MapLandmark.baduyPoints[0].coordinate,
            latitudinalMeters: 2_500, longitudinalMeters: 2_500)))
    }

    var body: some View {
        BaduyMapView(model: model, cameraMode: cameraMode, onLandmark: select, onCharacter: interact)
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Kanekes Village")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.05, green: 0.22, blue: 0.32))
                        Text("Leuwidamar, Lebak, Banten")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Color(red: 0.22, green: 0.40, blue: 0.39))
                    }
                    Spacer()
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(red: 0.04, green: 0.18, blue: 0.38))
                        .frame(width: 52, height: 52)
                        .background(MapPalette.paper, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
                .background(MapPalette.paper, in: UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
                .shadow(color: MapPalette.ink.opacity(0.08), radius: 12, y: 5)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        mapChip("Pertanian", icon: "leaf", gradient: MapPalette.forest)
                        mapChip("Perdagangan", icon: "basket", gradient: MapPalette.clay)
                        mapChip("Tradisi", icon: "square.grid.2x2", gradient: MapPalette.indigo)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 12)

                HStack(spacing: 0) {
                    cameraModeButton("Peta", icon: "map.fill", mode: .topDown)
                    cameraModeButton("Jelajah 3D", icon: "figure.walk", mode: .thirdPerson)
                }
                .padding(4)
                .background(MapPalette.paper, in: Capsule())
                .overlay(Capsule().stroke(Color(red: 0.05, green: 0.22, blue: 0.32).opacity(0.14)))
                .padding(.top, 10)

                HStack {
                    Spacer()
                    Button { } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(MapPalette.indigo, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                            .shadow(color: MapPalette.ink.opacity(0.18), radius: 6, y: 3)
                    }
                }
                .padding(.top, 14)
                .padding(.trailing, 16)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 12) {
                Button { focus(on: MapLandmark.baduyPoints[0].coordinate, metres: 2_500) } label: {
                    Text("S").font(.title3.weight(.bold)).foregroundStyle(MapPalette.ink)
                        .frame(width: 48, height: 48).background(MapPalette.paper, in: Circle())
                }
                Button {
                    guard let location = model.location else { return }
                    focus(on: location.coordinate, metres: 220)
                } label: {
                    Image(systemName: "location.fill").font(.title3).foregroundStyle(MapPalette.ink)
                        .frame(width: 48, height: 48).background(MapPalette.paper, in: Circle())
                }
            }
            .padding(.trailing, 20).padding(.bottom, 34)
        }
        .fullScreenCover(item: $arCharacter) { character in
            ARCharacterRoom(initialCharacter: character)
        }
        .sheet(item: $selectedCharacter) { character in
            CharacterConversationView(character: character)
        }
        .alert(item: $model.enteredLandmark) { landmark in
            Alert(title: Text(landmark.name), message: Text("Anda memasuki radius lokasi ini."),
                  dismissButton: .default(Text("OK")))
        }
        .onChange(of: selectedCharacter) { _, _ in joystick = .zero }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { date in
            let elapsed = date.timeIntervalSince(lastMovementTick)
            lastMovementTick = date
            guard scenePhase == .active, selectedCharacter == nil, arCharacter == nil, joystick != .zero else { return }
            model.moveDebugPlayer(east: Double(joystick.width), north: -Double(joystick.height), elapsed: elapsed)
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { date in
            interactionDate = date
            if let selectedCharacter, !model.canInteract(with: selectedCharacter, at: date) {
                self.selectedCharacter = nil
            }
        }
        .onChange(of: model.location) { _, location in
            interactionDate = .now
            if let location, !didFocusUser {
                didFocusUser = true
                focus(on: location.coordinate, metres: 220)
            }
            if let selectedCharacter, !model.canInteract(with: selectedCharacter) {
                self.selectedCharacter = nil
            }
        }
        .onAppear { model.start() }
        .onDisappear { joystick = .zero; model.stop() }
        .onChange(of: scenePhase) { _, phase in
            joystick = .zero
            lastMovementTick = .now
            if phase == .active { model.start() } else { model.stop() }
        }
    }

    private func interact(with character: BaduyCharacter) {
        guard model.canInteract(with: character) else { return }
        joystick = .zero
        if model.isAtCiboleger == false {
            arCharacter = character
        } else {
            selectedCharacter = character
        }
    }

    private func interactionDescription(_ character: BaduyCharacter) -> String {
        guard let distance = model.distance(to: character) else { return "Menunggu GPS akurat…" }
        if model.canInteract(with: character, at: interactionDate) { return model.isAtCiboleger == false ? "Masuk ruang AR" : "Ayo berbincang" }
        if distance <= model.interactionRadius { return "Menunggu GPS akurat…" }
        return "\(Int(distance)) m · terkunci"
    }

    private func select(_ landmark: MapLandmark) {
        model.selectedLandmark = landmark
        focus(on: landmark.coordinate, metres: 600)
    }

    private func focus(on coordinate: CLLocationCoordinate2D, metres: CLLocationDistance) {
        withAnimation {
            position = .region(MKCoordinateRegion(center: coordinate,
                latitudinalMeters: metres, longitudinalMeters: metres))
        }
    }

    private func mapChip(_ title: String, icon: String, gradient: LinearGradient) -> some View {
        Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(gradient, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
    }

    private func cameraModeButton(_ title: String, icon: String, mode: BaduyCameraMode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { cameraMode = mode }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(cameraMode == mode ? .white : Color(red: 0.05, green: 0.22, blue: 0.32))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    if cameraMode == mode {
                        Capsule().fill(MapPalette.indigo)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
