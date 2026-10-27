import SwiftUI
import Combine

private enum MapPalette {
    static let ink = Color(red: 0.08, green: 0.19, blue: 0.27)
    static let mist = Color(red: 0.91, green: 0.95, blue: 0.89)
    static let cream = Color(red: 1.0, green: 0.97, blue: 0.88)
    static let clay = Color(red: 0.64, green: 0.38, blue: 0.23)
    static let teal = Color(red: 0.20, green: 0.58, blue: 0.57)
    static let indigo = LinearGradient(
        colors: [Color(red: 0.20, green: 0.36, blue: 0.49), Color(red: 0.10, green: 0.22, blue: 0.36)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct MapTopChrome: View {
    let title: String
    let subtitle: String
    let status: String
    @Binding var cameraMode: BaduyCameraMode

    var body: some View {
        VStack(spacing: 10) {
            MapHeader(title: title, subtitle: subtitle, status: status)
            MapModePicker(cameraMode: $cameraMode)
        }
    }
}

private struct MapHeader: View {
    let title: String
    let subtitle: String
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mountain.2.fill")
                .font(.headline)
                .foregroundStyle(MapPalette.cream)
                .frame(width: 42, height: 42)
                .background(MapPalette.indigo, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(MapPalette.ink.opacity(0.68))
            }
            Spacer(minLength: 8)
            MapStatusBadge(status: status)
        }
        .foregroundStyle(MapPalette.ink)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: MapPalette.ink.opacity(0.14), radius: 18, y: 8)
    }
}

private struct MapStatusBadge: View {
    let status: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(MapPalette.teal)
                .frame(width: 7, height: 7)
            Text(status)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(MapPalette.mist.opacity(0.9), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

private struct MapModePicker: View {
    @Binding var cameraMode: BaduyCameraMode

    var body: some View {
        HStack(spacing: 4) {
            MapModeButton(title: "Peta", icon: "map.fill", mode: .topDown, selection: $cameraMode)
            MapModeButton(title: "Jelajah 3D", icon: "figure.walk", mode: .thirdPerson, selection: $cameraMode)
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.55), lineWidth: 1) }
        .shadow(color: MapPalette.ink.opacity(0.12), radius: 12, y: 5)
        .frame(maxWidth: 290)
    }
}

private struct MapModeButton: View {
    let title: LocalizedStringKey
    let icon: String
    let mode: BaduyCameraMode
    @Binding var selection: BaduyCameraMode

    var body: some View {
        let isSelected = selection == mode
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                selection = mode
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : MapPalette.ink)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(MapPalette.indigo.opacity(isSelected ? 1 : 0), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MapBottomChrome: View {
    let cameraMode: BaduyCameraMode

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 12) {
                MapLegend()
                Spacer(minLength: 12)
                MapGestureHint(cameraMode: cameraMode)
            }
            VStack(alignment: .leading, spacing: 10) {
                MapGestureHint(cameraMode: cameraMode)
                MapLegend()
            }
        }
    }
}

private struct MapLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LEGENDA")
                .font(.caption2.weight(.bold))
                .foregroundStyle(MapPalette.ink.opacity(0.58))
            HStack(spacing: 12) {
                LegendItem(title: "Kampung", color: MapPalette.clay)
                LegendItem(title: "Tokoh", color: MapPalette.cream)
                LegendItem(title: "Posisi", color: MapPalette.teal)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .mapChrome(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct LegendItem: View {
    let title: LocalizedStringKey
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay { Circle().stroke(MapPalette.ink.opacity(0.2), lineWidth: 0.5) }
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(MapPalette.ink)
    }
}

private struct MapGestureHint: View {
    let cameraMode: BaduyCameraMode

    var body: some View {
        Label(
            cameraMode == .topDown ? "Geser dan cubit peta" : "Geser untuk melihat sekitar",
            systemImage: cameraMode == .topDown ? "hand.draw.fill" : "rotate.3d.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(MapPalette.ink)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .mapChrome(shape: Capsule())
    }
}

private extension View {
    func mapChrome<S: InsettableShape>(shape: S) -> some View {
        background(.ultraThinMaterial, in: shape)
            .overlay { shape.stroke(.white.opacity(0.5), lineWidth: 1) }
            .shadow(color: MapPalette.ink.opacity(0.12), radius: 12, y: 5)
    }
}

struct HomeView: View {
    @State private var model: HomeViewModel
    @State private var joystick = CGSize.zero
    @State private var lastMovementTick = Date.now
    @State private var interactionDate = Date.now
    @State private var selectedCharacter: BaduyCharacter?
    @State private var arCharacter: BaduyCharacter?
    @State private var arObject: BaduyARObject?
    @State private var cameraMode: BaduyCameraMode = .topDown
    @Environment(\.scenePhase) private var scenePhase

    init(model: HomeViewModel? = nil) {
        _model = State(initialValue: model ?? HomeViewModel(landmarks: MapLandmark.baduyPoints))
    }

    var body: some View {
        Group {
            if arObject == nil && arCharacter == nil {
                BaduyMapView(
                    model: model,
                    cameraMode: cameraMode,
                    onLandmark: select,
                    onCharacter: interact,
                    onObject: openObject
                )
            } else {
                MapPalette.cream
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            VStack(alignment: .trailing, spacing: 12) {
                MapTopChrome(
                title: model.currentGeofence?.name ?? "Kanekes",
                subtitle: model.currentGeofence.map { "Dalam radius · \($0.name)" }
                    ?? "Leuwidamar · Lebak · Banten",
                status: model.status,
                cameraMode: $cameraMode
            )
                Menu {
                    ForEach(BaduyARObject.allCases) { object in
                        Button(object.title, systemImage: object.symbol) {
                            joystick = .zero
                            arObject = object
                        }
                    }
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(MapPalette.indigo, in: Circle())
                }
                .accessibilityLabel("Jelajahi objek dalam AR")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottomLeading) {
            MapBottomChrome(cameraMode: cameraMode)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .fullScreenCover(item: $arCharacter) { character in
            ARCharacterRoom(initialCharacter: character)
        }
        .fullScreenCover(item: $arObject) { object in
            ARObjectRoom(initialObject: object)
        }
        .sheet(item: $selectedCharacter) { character in
            CharacterConversationView(character: character)
        }
        .sheet(item: $model.selectedLandmark) { landmark in
            BaduyInfoSheet(
                title: landmark.name,
                paragraphs: [
                    landmark.detail.isEmpty
                        ? "Jelajahi lokasi ini di kawasan Kanekes."
                        : landmark.detail
                ],
                style: .white,
                closeAction: { model.selectedLandmark = nil }
            )
            .baduySheetPresentation(interactable: true)
        }
        .alert(item: $model.enteredLandmark) { landmark in
            Alert(title: Text(landmark.name), message: Text("Anda memasuki radius lokasi ini."),
                  dismissButton: .default(Text("OK")))
        }
        .onChange(of: selectedCharacter) { _, _ in joystick = .zero }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { date in
            let elapsed = date.timeIntervalSince(lastMovementTick)
            lastMovementTick = date
            guard scenePhase == .active, selectedCharacter == nil, arCharacter == nil, arObject == nil, joystick != .zero else { return }
            model.moveDebugPlayer(east: Double(joystick.width), north: -Double(joystick.height), elapsed: elapsed)
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { date in
            interactionDate = date
            if let selectedCharacter, !model.canInteract(with: selectedCharacter, at: date) {
                self.selectedCharacter = nil
            }
        }
        .onChange(of: model.location) { _, _ in
            interactionDate = .now
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

    private func openObject(_ object: BaduyARObject) {
        joystick = .zero
        arObject = object
    }

    private func select(_ landmark: MapLandmark) {
        model.selectedLandmark = landmark
    }
}
