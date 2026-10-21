import SwiftUI

struct DebugJoystick: View {
    @Binding var direction: CGSize
    @GestureState private var translation = CGSize.zero
    private let radius: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(.blue.opacity(0.12))
            Circle().strokeBorder(.blue.opacity(0.4), lineWidth: 2)
            Image(systemName: "plus").foregroundStyle(.blue.opacity(0.3))
            Circle().fill(.blue.gradient).frame(width: 42, height: 42)
                .offset(x: normalized(translation).width * radius,
                        y: normalized(translation).height * radius)
        }
        .frame(width: 112, height: 112)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .updating($translation) { value, state, _ in state = value.translation }
            .onChanged { direction = normalized($0.translation) }
            .onEnded { _ in direction = .zero })
        .onChange(of: translation) { _, value in
            if value == .zero { direction = .zero }
        }
        .onDisappear { direction = .zero }
        .accessibilityLabel("Analog gerak pemain")
        .accessibilityHint("Geser untuk bergerak. Lepaskan untuk berhenti.")
    }

    private func normalized(_ offset: CGSize) -> CGSize {
        let length = hypot(offset.width, offset.height)
        guard length > 3 else { return .zero }
        let divisor = max(radius, length)
        return CGSize(width: offset.width / divisor, height: offset.height / divisor)
    }
}
