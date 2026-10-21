import SwiftUI
import MapKit
import Combine

struct HomeView: View {
    @State private var model: HomeViewModel
    @State private var position: MapCameraPosition
    @State private var joystick = CGSize.zero
    @State private var lastMovementTick = Date.now
    @State private var didFocusUser = false
    @State private var interactionDate = Date.now
    @State private var selectedCharacter: BaduyCharacter?
    @State private var arCharacter: BaduyCharacter?
    @Environment(\.scenePhase) private var scenePhase

    init(model: HomeViewModel? = nil) {
        let model = model ?? HomeViewModel(landmarks: MapLandmark.baduyPoints)
        _model = State(initialValue: model)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: model.landmarks.first?.coordinate ?? MapLandmark.baduyPoints[0].coordinate,
            latitudinalMeters: 2_500, longitudinalMeters: 2_500)))
    }

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            if model.isDebugMode {
                if let location = model.location {
                    Annotation("Anda · Debug", coordinate: location.coordinate) {
                        Image(systemName: "figure.walk.circle.fill")
                            .font(.largeTitle).foregroundStyle(.white, .blue)
                            .background(.white, in: Circle())
                    }
                }
            } else {
                UserAnnotation()
            }
            ForEach(model.landmarks) { landmark in
                Annotation(landmark.name, coordinate: landmark.coordinate) {
                    Button { select(landmark) } label: {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, model.selectedLandmark?.id == landmark.id ? .blue : .orange)
                            .padding(6).background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel(landmark.name)
                }
            }
            ForEach(BaduyCharacter.allCases) { character in
                if let coordinate = model.coordinate(for: character) {
                    Annotation(character.title, coordinate: coordinate) {
                        Button { interact(with: character) } label: {
                            CharacterMapIcon(character: character,
                                unlocked: model.canInteract(with: character, at: interactionDate))
                        }
                        .disabled(!model.canInteract(with: character, at: interactionDate))
                        .accessibilityLabel("\(character.title), \(interactionDescription(character))")
                    }
                }
            }
            ForEach(model.trails.indices, id: \.self) { index in
                MapPolyline(coordinates: model.trails[index]).stroke(.orange, lineWidth: 4)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Peta Baduy").font(.headline)
                Text(model.isAtCiboleger == true ? "Jelajahi Baduy" : "Temui dua karakter di sekitar Anda").font(.subheadline)
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                #if DEBUG
                Toggle("Debug analog", isOn: Binding(get: { model.isDebugMode }, set: { enabled in
                    joystick = .zero
                    selectedCharacter = nil
                    didFocusUser = false
                    model.setDebugMode(enabled)
                    if let location = model.location { focus(on: location.coordinate, metres: 220) }
                }))
                #endif
            }
            .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                if model.isDebugMode {
                    HStack {
                        DebugJoystick(direction: $joystick)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Analog · 8 m/detik").font(.caption)
                            Text("Atas = utara").font(.caption).foregroundStyle(.secondary)
                            Button("Reset posisi") {
                                joystick = .zero
                                selectedCharacter = nil
                                model.resetDebugPosition()
                                if let location = model.location { focus(on: location.coordinate, metres: 220) }
                            }
                        }
                        Spacer()
                    }
                }
                HStack {
                    Button("Ke Baduy", systemImage: "map") {
                        focus(on: MapLandmark.baduyPoints[0].coordinate, metres: 2_500)
                    }
                    Spacer()
                    Button("Lokasi saya", systemImage: "location.fill") {
                        guard let location = model.location else { return }
                        model.selectedLandmark = nil
                        focus(on: location.coordinate, metres: 220)
                    }.disabled(model.location == nil)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(model.landmarks) { landmark in
                            Button(landmark.name) { select(landmark) }
                                .buttonStyle(.bordered)
                                .tint(model.selectedLandmark?.id == landmark.id ? .blue : .primary)
                        }
                    }
                }
                if let landmark = model.selectedLandmark {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(landmark.name).font(.headline)
                            Text(landmark.detail).font(.subheadline)
                            if let metres = model.distance(to: landmark) {
                                Text(metres < 1_000 ? "\(Int(metres)) m dari lokasi Anda" : "\((metres / 1_000).formatted(.number.precision(.fractionLength(1)))) km dari lokasi Anda")
                                    .font(.caption)
                            }
                            if let source = landmark.sourceURL, let url = URL(string: source) {
                                Link("Referensi lokasi", destination: url).font(.caption)
                            }
                        }
                        Spacer()
                        Button("Tutup") { model.selectedLandmark = nil }
                    }
                }
                Text(model.isAtCiboleger == false ? "Dekati hingga 20 m, lalu ketuk karakter untuk masuk ruang AR." : "Dekati karakter hingga 20 m untuk berbincang.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach(BaduyCharacter.allCases) { character in
                        Button { interact(with: character) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(character.title)
                                Text(interactionDescription(character)).font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canInteract(with: character, at: interactionDate))
                    }
                }
            }
            .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding()
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
}
