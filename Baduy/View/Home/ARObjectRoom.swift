import SwiftUI
import ARKit
import AVFoundation
import RealityKit

/// Camera permission, object selection and native Baduy information sheets.
struct ARObjectRoom: View {
    let initialObject: BaduyARObject
    @State private var selection: BaduyARObject
    @StateObject private var scene = ARObjectScene()
    @State private var cameraReady = false
    @State private var permissionMessage: String?
    @State private var showSettings = false
    @State private var showInfo = false
    @State private var infoDetent: PresentationDetent = .medium
    @State private var infoHeight: CGFloat = 0
    @State private var retryID = 0
    @State private var narrator = AVSpeechSynthesizer()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(initialObject: BaduyARObject) {
        self.initialObject = initialObject
        _selection = State(initialValue: initialObject)
    }

    var body: some View {
        ZStack {
            if cameraReady {
                ARObjectCamera(scene: scene)
                    .ignoresSafeArea()
                    .task(id: "\(selection.id)-\(retryID)") { await scene.load(selection) }
            } else if let permissionMessage {
                ContentUnavailableView {
                    Label("Ruang AR belum tersedia", systemImage: "camera")
                } description: {
                    Text(permissionMessage)
                } actions: {
                    if showSettings {
                        Button("Buka Pengaturan") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    Button("Kembali ke peta") { dismiss() }
                }
            } else {
                ProgressView("Menyiapkan kamera AR…")
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text(selection.title).font(.headline)
                Spacer()
                Button("Tutup", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)
        }
        .safeAreaInset(edge: .bottom) {
            if cameraReady {
                VStack(spacing: 12) {
                    if scene.loading {
                        ProgressView("Memuat \(selection.title)…")
                    } else if let error = scene.error {
                        Text(error).font(.subheadline)
                        Button("Coba lagi") { retryID += 1 }
                    } else {
                        Text(scene.guidance).font(.subheadline)
                            .multilineTextAlignment(.center)
                    }
                    Text(scene.interactionStatus).font(.caption)
                    Button("Tes getaran", action: scene.playWeavingHaptic)
                    HStack {
                        Menu {
                            ForEach(BaduyARObject.allCases) { item in
                                Button(item.title, systemImage: item.symbol) {
                                    selection = item
                                }
                            }
                        } label: {
                            Label("Ganti objek", systemImage: "cube.transparent")
                        }
                        .disabled(scene.loading)
                        Spacer()
                        Button("Atur ulang", systemImage: "arrow.counterclockwise") {
                            scene.reposition()
                        }.disabled(!scene.placed)
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    Button("Kenali \(selection.title)") {
                        infoDetent = .medium
                        showInfo = true
                    }
                        .buttonStyle(BaduySheetButtonStyle())
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showInfo, onDismiss: {
            infoHeight = 0
            scene.setInformationLayout(height: 0, expanded: false)
        }) {
            Group {
                if selection == .lumbung {
                    BaduyInfoSheet(title: selection.title, paragraphs: selection.paragraphs,
                                   style: .white, closeAction: { showInfo = false })
                } else {
                    WeavingInfoSheet(
                        onFinish: { showInfo = false },
                        onObjectChange: { object in selection = object }
                    )
                }
            }
            .baduySheetPresentation(detents: [.medium, .large], interactable: true)
            .presentationDetents([.medium, .large], selection: $infoDetent)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height + geometry.safeAreaInsets.bottom
            } action: { height in
                infoHeight = height
                scene.setInformationLayout(height: height, expanded: infoDetent == .large)
            }
            .onChange(of: infoDetent) { _, detent in
                scene.setInformationLayout(height: infoHeight, expanded: detent == .large)
            }
        }
        .task {
            guard ARWorldTrackingConfiguration.isSupported else {
                permissionMessage = "Gunakan iPhone atau iPad yang mendukung ARKit untuk menempatkan objek di lingkungan sekitar. Kamera AR tidak tersedia di Simulator."
                return
            }
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            guard !Task.isCancelled else { return }
            cameraReady = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            if !cameraReady {
                showSettings = true
                permissionMessage = "Izinkan akses kamera di Pengaturan untuk melihat lumbung dan alat tenun dalam AR."
            }
        }
        .onChange(of: selection) { _, _ in narrator.stopSpeaking(at: .immediate) }
        .onDisappear { narrator.stopSpeaking(at: .immediate); scene.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { scene.stop(); dismiss() }
        }
    }
}

private struct ARObjectCamera: UIViewRepresentable {
    let scene: ARObjectScene

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        // A dedicated touch surface isolates manipulation from ARView's internal
        // recognizers. Its coordinates match the camera exactly.
        let input = UIView()
        input.backgroundColor = .clear
        for child in [view, input] {
            child.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                child.topAnchor.constraint(equalTo: container.topAnchor),
                child.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        scene.attach(to: view, inputView: input)
        return container
    }

    func updateUIView(_ view: UIView, context: Context) {}

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        for case let camera as ARView in view.subviews {
            camera.session.pause()
            camera.scene.anchors.removeAll()
        }
    }
}
