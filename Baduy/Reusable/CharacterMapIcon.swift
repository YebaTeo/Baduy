import SwiftUI

/// A lightweight custom MapKit annotation, with no 3D asset loading.
struct CharacterMapIcon: View {
    let character: BaduyCharacter
    let unlocked: Bool

    private var accent: Color { character == .cowo ? .teal : .purple }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(.regularMaterial)
                Circle().strokeBorder(accent, lineWidth: unlocked ? 3 : 1)
                VStack(spacing: -3) {
                    ZStack(alignment: .top) {
                        if character == .cewe {
                            Capsule().fill(Color(white: 0.15)).frame(width: 29, height: 34)
                        }
                        Ellipse().fill(Color(red: 0.76, green: 0.54, blue: 0.36))
                            .frame(width: 23, height: 28)
                        UnevenRoundedRectangle(topLeadingRadius: 9, topTrailingRadius: 9)
                            .fill(character == .cowo ? .white : Color(white: 0.15))
                            .frame(width: 27, height: 10)
                        HStack(spacing: 7) {
                            Circle().frame(width: 2, height: 2)
                            Circle().frame(width: 2, height: 2)
                        }.foregroundStyle(.black).padding(.top, 14)
                    }.frame(height: 32)
                    UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                        .fill(character == .cowo ? Color(white: 0.95) : Color(white: 0.18))
                        .frame(width: 36, height: 22)
                        .overlay(alignment: .center) {
                            Rectangle().fill(accent).frame(width: 4, height: 20)
                        }
                }
                .clipShape(Circle())
                .padding(7)
            }.frame(width: 64, height: 64)
            Image(systemName: unlocked ? "bubble.left.fill" : "lock.fill")
                .font(.caption2.bold()).foregroundStyle(.white)
                .padding(6).background(accent, in: Circle())
        }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        .accessibilityHidden(true)
    }
}
