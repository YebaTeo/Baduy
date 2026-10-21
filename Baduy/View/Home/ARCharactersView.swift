import SwiftUI
import RealityKit

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


@MainActor
extension BaduyCharacter {
    private static var models: [BaduyCharacter: Entity] = [:]
    private static var temporarySharedModel: Entity?

    /// Both worlds share imported mesh/texture resources, with independent entity transforms.
    func makeEntity(height: Float = 0.9) async throws -> Entity {
        // Temporary lightweight asset used for both interaction points while
        // the final character models are being optimized.
        let resourceName = "seahorse"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "usdz") else {
            print("[Baduy][USDZ] MISSING: \(resourceName).usdz in Bundle.main")
            throw CocoaError(.fileNoSuchFile)
        }
        print("[Baduy][USDZ] START \(resourceName).usdz for \(rawValue) path=\(url.path)")
        let template: Entity
        if let cached = Self.models[self] {
            template = cached
        } else if let shared = Self.temporarySharedModel {
            template = shared
            Self.models[self] = shared
        } else {
            template = try await Entity(contentsOf: url)
            Self.temporarySharedModel = template
            Self.models[self] = template
        }
        print("[Baduy][USDZ] DECODED \(rawValue).usdz")
        let model = template.clone(recursive: true)
        try Task.checkCancellation()
        let bounds = model.visualBounds(relativeTo: nil)
        guard bounds.extents.y.isFinite, bounds.extents.y > 0.001 else {
            print("[Baduy][USDZ] INVALID_BOUNDS \(rawValue) bounds=\(bounds)")
            throw CocoaError(.fileReadCorruptFile)
        }
        print("[Baduy][USDZ] BOUNDS \(rawValue) extents=\(bounds.extents)")
        // Normalize height and put the feet at the local ground origin.
        let scale: Float = height / bounds.extents.y
        let scaled = Entity()
        scaled.scale = SIMD3(repeating: scale)
        scaled.addChild(model)
        let root = Entity()
        root.addChild(scaled)
        let fitted = scaled.visualBounds(relativeTo: root)
        scaled.position = [-fitted.center.x, -fitted.min.y, -fitted.center.z]
        // A simple proxy avoids expensive mesh collision generation on imported assets.
        root.components.set(CollisionComponent(shapes: [
            .generateBox(size: [max(0.3, fitted.extents.x), height, max(0.25, fitted.extents.z)])
                .offsetBy(translation: [0, height / 2, 0])
        ]))
        root.components.set(InputTargetComponent())
        print("[Baduy][USDZ] READY \(rawValue) height=\(height) scale=\(scale)")
        return root
    }
}

struct ARCharactersView: View {
    let initialCharacter: BaduyCharacter
    @State private var scene = CharacterScene()
    @State private var selected: BaduyCharacter?
    @State private var page = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        RealityView { content in
            content.camera = .spatialTracking
            content.add(scene.anchor)
            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                let anchored = scene.anchor.isAnchored
                if scene.placed != anchored { scene.placed = anchored }
            }
            await scene.startTracking()
            guard !Task.isCancelled else { return }
            await scene.load()
        }
        .ignoresSafeArea()
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            guard scene.placed, let character = scene.character(for: value.entity) else { return }
            select(character)
        })
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if scene.loading { ProgressView("Memuat karakter…") }
                if scene.placed && !scene.loaded.isEmpty {
                    Label("Bidang terdeteksi · karakter terpasang otomatis", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                if !scene.placed {
                    Text("Arahkan kamera ke lantai dan gerakkan perlahan untuk menempatkan dua karakter.")
                        .font(.subheadline).multilineTextAlignment(.center)
                }
                if let error = scene.error { Text(error).font(.caption).foregroundStyle(.red) }
                HStack {
                    ForEach(BaduyCharacter.allCases) { character in
                        Button(character.title) { select(character) }
                            .buttonStyle(.bordered)
                            .tint(character == .cowo ? .cyan : .purple)
                            .disabled(!scene.loaded.contains(character) || !scene.placed)
                    }
                }
                if let selected, scene.placed, scene.loaded.contains(selected) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(selected.title).font(.headline)
                            Spacer()
                            Button("Tutup") { self.selected = nil }
                        }
                        Text(selected.lines[page]).font(.body)
                        HStack {
                            Button("Sebelumnya") { page -= 1 }.disabled(page == 0)
                            Spacer()
                            Text("\(page + 1)/\(selected.lines.count)").font(.caption)
                            Spacer()
                            Button("Berikutnya") { page += 1 }.disabled(page == selected.lines.count - 1)
                        }
                        Link("Sumber materi", destination: selected.source).font(.caption)
                    }
                } else if scene.placed && !scene.loading {
                    Text("Ketuk karakter untuk mulai berbincang.").font(.subheadline)
                }
                Button("Ayo ke Baduy · Lihat Ciboleger", systemImage: "location.fill") {
                    let coordinate = MapLandmark.baduyPoints[0].coordinate
                    if let url = URL(string: "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=Ciboleger") {
                        openURL(url)
                    }
                }.font(.subheadline)
            }
            .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)).padding()
        }
        .onAppear { select(initialCharacter) }
        .onDisappear {
            scene.stop()
        }
    }

    private func select(_ character: BaduyCharacter) {
        page = 0
        selected = character
    }
}

@MainActor
@Observable
private final class CharacterScene {
    let anchor = AnchorEntity(plane: .horizontal, minimumBounds: [0.1, 0.1])
    @ObservationIgnored private let trackingSession = SpatialTrackingSession()
    @ObservationIgnored private var stopped = false
    var placed = false
    private(set) var loading = true
    private(set) var loaded: Set<BaduyCharacter> = []
    private(set) var error: String?
    @ObservationIgnored var subscription: EventSubscription?
    private var roots: [BaduyCharacter: Entity] = [:]

    func startTracking() async {
        let unavailable = await trackingSession.run(.init(tracking: [.plane], camera: .back))
        if stopped || Task.isCancelled {
            await trackingSession.stop()
            return
        }
        if unavailable?.anchor.contains(.plane) == true {
            error = "Pelacakan bidang tidak tersedia pada perangkat ini."
        }
    }

    func stop() {
        stopped = true
        subscription?.cancel()
        subscription = nil
        Task { await trackingSession.stop() }
    }

    func load() async {
        print("[Baduy][AR] load start")
        defer { loading = false }
        guard !stopped, !Task.isCancelled else { return }
        for character in BaduyCharacter.allCases {
            do {
                let root = try await character.makeEntity()
                root.position.x = character == .cowo ? -0.5 : 0.5
                guard !stopped, !Task.isCancelled else { return }
                roots[character] = root
                anchor.addChild(root)
                // A visible placement pad confirms that the plane anchor is active
                // even when the imported character has a dark/transparent material.
                let pad = ModelEntity(
                    mesh: .generateCylinder(height: 0.015, radius: 0.28),
                    materials: [UnlitMaterial(color: character == .cowo ? .cyan : .systemPurple)]
                )
                pad.position = root.position
                anchor.addChild(pad)
                loaded.insert(character)
            } catch is CancellationError {
                return
            } catch {
                self.error = "Gagal memuat \(character.rawValue).usdz: \(error.localizedDescription)"
                print("[Baduy][AR] ERROR \(character.rawValue): \(error)")
            }
        }
        print("[Baduy][AR] load complete loaded=\(loaded)")
    }

    func character(for entity: Entity) -> BaduyCharacter? {
        var current: Entity? = entity
        while let candidate = current {
            if let match = roots.first(where: { $0.value === candidate }) { return match.key }
            current = candidate.parent
        }
        return nil
    }
}
