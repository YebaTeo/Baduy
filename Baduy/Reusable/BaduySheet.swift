import SwiftUI

/// Colors and textile treatment shared by Baduy's sheets.
enum BaduySheetStyle {
    case navy, white

    static let ink = Color(red: 0.10, green: 0.23, blue: 0.40)
    static let surface = Color(red: 0.89, green: 0.95, blue: 0.92)
}

/// Uses the supplied two-swatch image unchanged. Only one swatch is visible.
private struct KainSheetBackground: View {
    let style: BaduySheetStyle
    var patternOpacity: Double = 1

    var body: some View {
        GeometryReader { geometry in
            let height = min(220.0, geometry.size.height * 0.42)
            ZStack(alignment: .bottom) {
                BaduySheetStyle.surface
                GeometryReader { swatch in
                    Image("KainSwatches")
                        .resizable()
                        .frame(width: swatch.size.width, height: swatch.size.height * 566 / 270)
                        .offset(y: style == .navy ? 0 : -swatch.size.height * 296 / 270)
                }
                .frame(height: height)
                .clipped()
                .opacity(patternOpacity)
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.35), location: 0.45),
                    .init(color: .black, location: 1)
                ], startPoint: .top, endPoint: .bottom))

            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Reusable scrollable sheet body. Present with `.sheet` and apply
/// `.baduySheetPresentation()` to opt into the native detents and drag handle.
struct BaduySheet<Content: View>: View {
    let title: String
    var style: BaduySheetStyle = .navy
    var audioAction: (() -> Void)? = nil
    var closeAction: (() -> Void)? = nil
    /// A short teaser for the collapsed sheet. Full content is only shown expanded.
    var compactSummary: String? = nil
    /// Pinned above the bottom safe area in the expanded sheet.
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var pageLabel: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 250
            let patternOpacity = min(1, max(0, (geometry.size.height - 250) / 130))
            VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let audioAction {
                    Button(action: audioAction) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .padding(7)
                            .background(.white.opacity(0.85), in: Circle())
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Dengarkan \(title)")
                }
                Spacer(minLength: 0)
                if let pageLabel {
                    Text(pageLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BaduySheetStyle.ink.opacity(0.55))
                        .accessibilityLabel("Halaman \(pageLabel)")
                }
                if let closeAction {
                    Button(action: closeAction) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Tutup")
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 24)
            .padding(.top, compact ? 12 : 16)

            if compact {
                ViewThatFits(in: .vertical) {
                    compactPreview(lines: 4)
                    compactPreview(lines: 3)
                    compactPreview(lines: 2)
                    compactPreview(lines: 1)
                    Color.clear.frame(height: 0)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 12)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content()
                }
                .font(.body)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, actionTitle != nil && action != nil ? 24 : 170)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
            .clipped()
            // A sibling footer reserves space instead of drawing over scroll content.
            if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(BaduySheetButtonStyle())
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
            }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                KainSheetBackground(style: style, patternOpacity: patternOpacity)
            }
        }
        .foregroundStyle(BaduySheetStyle.ink)
        .tint(BaduySheetStyle.ink)
    }

    @ViewBuilder
    private func compactPreview(lines: Int) -> some View {
        if let compactSummary, !compactSummary.isEmpty {
            Text(compactSummary)
                .font(.body)
                .lineSpacing(4)
                .lineLimit(lines)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A data-driven information sheet, with optional audio and primary action.
struct BaduyInfoSheet: View {
    let title: String
    let paragraphs: [String]
    var style: BaduySheetStyle = .navy
    var audioAction: (() -> Void)? = nil
    var closeAction: (() -> Void)? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var compactSummary: String? = nil

    var body: some View {
        BaduySheet(title: title, style: style, audioAction: audioAction,
                   closeAction: closeAction, compactSummary: compactSummary ?? paragraphs.first,
                   actionTitle: actionTitle, action: action) {
            ForEach(paragraphs.indices, id: \.self) { index in
                Text(paragraphs[index]).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct BaduySheetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(BaduySheetStyle.ink.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}

/// Room for the handle, title and two-line teaser. Accessibility text sizes
/// use the scrollable medium/large presentations instead of a cramped preview.
private struct BaduyCompactDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        guard !context.dynamicTypeSize.isAccessibilitySize else { return nil }
        // System sheets add the bottom safe area to this content height.
        // Budget only for the header, two lines of copy and their spacing.
        switch context.dynamicTypeSize {
        case .xxxLarge: return 212
        case .xxLarge: return 188
        case .xLarge: return 164
        default: return 140
        }
    }
}

extension PresentationDetent {
    static let baduyCompact = PresentationDetent.custom(BaduyCompactDetent.self)
}

extension View {
    /// Set `interactable` for AR/map sheets whose background remains usable.
    func baduySheetPresentation(
        detents: Set<PresentationDetent> = [.baduyCompact, .medium, .large],
        interactable: Bool = false
    ) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(BaduySheetStyle.surface)
            .presentationBackgroundInteraction(interactable ? .enabled : .disabled)
    }
}

private struct BaduySheetPreview: View {
    @ViewState private var presented = true
    let style: BaduySheetStyle

    var body: some View {
        ZStack {
            Color(red: 0.28, green: 0.38, blue: 0.31).ignoresSafeArea()
            Button("Buka lembar informasi") { presented = true }
                .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $presented) {
            BaduyInfoSheet(
                title: "Memintal Benang",
                paragraphs: [
                    "Sebelum mulai menenun, siapin benangnya dulu, euy. Serat kapas téh diputar terus digulung biar jadi benang yang panjang dan kuat.",
                    "Penasaran bagaimana proses menenun? Yuk, kenali ceritanya bersama para penenun."
                ],
                style: style,
                actionTitle: "Yuk, tanya ke para penenun!",
                action: { presented = false }
            )
            .baduySheetPresentation()
        }
    }
}
