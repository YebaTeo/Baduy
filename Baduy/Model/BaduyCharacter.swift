import Foundation
import CoreLocation

/// General introductory material; Sundanese phrases are not a claim about the Baduy dialect.
enum BaduyCharacter: String, CaseIterable, Identifiable {
    case cowo, cewe
    var id: String { rawValue }
    var title: String { self == .cowo ? "Tentang Baduy" : "Frasa Sunda" }
    var lines: [String] {
        switch self {
        case .cowo:
            return [
                "Halo! Mari mengenal Baduy. Masyarakat Baduy tinggal di wilayah Kanekes, Kabupaten Lebak, Banten.",
                "Masyarakat Baduy dikenal dengan kelompok Baduy Dalam dan Baduy Luar. Keduanya memiliki kehidupan dan tradisi adat yang perlu kita hormati.",
                "Saat berkunjung, ikuti arahan masyarakat setempat dan jaga lingkungan. Yuk, kenali Baduy secara langsung!"
            ]
        case .cewe:
            return [
                "Wilujeng énjing — Selamat pagi. Gunakan sapaan ini saat bertemu seseorang pada pagi hari.",
                "Hatur nuhun — Terima kasih. Ucapkan setelah menerima bantuan atau pemberian.",
                "Wilujeng sonten — Selamat sore. Ini sapaan untuk bertemu seseorang pada sore hari. Frasa di sini adalah bahasa Sunda umum."
            ]
        }
    }
    var source: URL {
        switch self {
        case .cowo: URL(string: "https://setneg.go.id/baca/index/berburu_cendera_mata_ke_pemukiman_baduy")!
        case .cewe: URL(string: "https://repository.upi.edu/27274/1/Pro_2017_Seminar%20Tahunan%20Linguistik_UPI.pdf")!
        }
    }
}


extension BaduyCharacter {
    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .cowo: .init(latitude: -6.5948, longitude: 106.2259)
        case .cewe: .init(latitude: -6.5953, longitude: 106.2262)
        }
    }
}
