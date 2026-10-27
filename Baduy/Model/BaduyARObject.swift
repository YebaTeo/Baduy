import Foundation

/// Bundled cultural objects available from the map's AR menu.
enum BaduyARObject: String, CaseIterable, Identifiable {
    case lumbung, pintal, tenun

    var id: String { rawValue }
    var resourceName: String { rawValue }
    var title: String {
        switch self {
        case .lumbung: "Lumbung Padi"
        case .pintal: "Memintal Benang"
        case .tenun: "Proses Menenun"
        }
    }
    var symbol: String {
        switch self {
        case .lumbung: "house.fill"
        case .pintal: "circle.dotted.circle"
        case .tenun: "square.grid.3x3.fill"
        }
    }
    /// Comfortable display size, not a claim about the object's real dimensions.
    var displaySpan: Float { self == .lumbung ? 1.2 : 0.8 }
    var paragraphs: [String] {
        switch self {
        case .lumbung:
            ["Lumbung digunakan untuk menyimpan padi. Amati bentuk bangunan, bagian atap, dan penyangganya melalui model ini.",
             "Model ditampilkan dalam ukuran peraga agar mudah diamati di sekitar Anda."]
        case .pintal:
            ["Pemintalan mengolah serat menjadi benang yang dapat digunakan untuk menenun. Amati roda dan bagian penyangga alat pada model ini.",
             "Putar model untuk melihat bentuk alat dari berbagai sisi."]
        case .tenun:
            ["Kain tenun dibuat dengan menyilangkan benang. Amati susunan alat dan posisi kain pada model ini.",
             "Dekati model atau ubah ukurannya untuk melihat bagian alat dengan lebih jelas."]
        }
    }
}
