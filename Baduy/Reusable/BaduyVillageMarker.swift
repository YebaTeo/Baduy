import SwiftUI

/// An illustrative stilt-house symbol, not a surveyed building footprint.
struct BaduyVillageMarker: View {
    let selected: Bool
    private var ink: Color { Color(red: 0.08, green: 0.17, blue: 0.28) }

    var body: some View {
        Canvas { context, _ in
            let wall = CGRect(x: 12, y: 24, width: 32, height: 21)
            context.fill(Path(wall), with: .color(Color(red: 0.30, green: 0.48, blue: 0.37)))
            context.stroke(Path(wall), with: .color(ink), lineWidth: 1.5)
            var supports = Path()
            for x in [CGFloat(15), 28, 41] {
                supports.move(to: CGPoint(x: x, y: 45))
                supports.addLine(to: CGPoint(x: x, y: 52))
            }
            context.stroke(supports, with: .color(ink), lineWidth: 2)
            var roof = Path()
            roof.move(to: CGPoint(x: 6, y: 26))
            roof.addLine(to: CGPoint(x: 17, y: 10))
            roof.addLine(to: CGPoint(x: 39, y: 10))
            roof.addLine(to: CGPoint(x: 50, y: 26))
            roof.closeSubpath()
            context.fill(roof, with: .color(ink))
            var thatch = Path()
            for x in stride(from: CGFloat(17), through: 39, by: 4) {
                thatch.move(to: CGPoint(x: x, y: 13))
                thatch.addLine(to: CGPoint(x: x, y: 23))
            }
            context.stroke(thatch, with: .color(.white.opacity(0.3)), lineWidth: 1)
            context.fill(Path(CGRect(x: 25, y: 32, width: 7, height: 13)), with: .color(ink))
            context.stroke(Path(CGRect(x: 16, y: 31, width: 5, height: 6)), with: .color(ink), lineWidth: 1)
        }
        .frame(width: 56, height: 56)
        .padding(3)
        .background(Color(red: 0.68, green: 0.77, blue: 0.85), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(ink.opacity(selected ? 1 : 0.45), lineWidth: selected ? 3 : 1)
        }
        .overlay {
            // Small diamond weave accent inspired by Baduy textile motifs.
            Image(systemName: "diamond.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color(red: 0.88, green: 0.78, blue: 0.48).opacity(0.85))
                .offset(x: 19, y: 19)
        }
        .shadow(color: ink.opacity(0.15), radius: 2, y: 2)
        .accessibilityHidden(true)
    }
}
