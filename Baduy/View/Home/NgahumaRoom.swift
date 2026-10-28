import ARKit
import AVFoundation
import RealityKit
import SwiftUI

struct NgahumaRoom: View {
    @StateObject private var scene = NgahumaScene()
    @State private var cameraReady = false
    @State private var preview = false
    @State private var permissionChecked = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.13, blue: 0.10).ignoresSafeArea()
            if cameraReady || preview {
                NgahumaCamera(scene: scene, preview: preview).ignoresSafeArea()
                    .task { await scene.prepareAssets(); await scene.loadAudio() }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "leaf.fill").font(.system(size: 52)).foregroundStyle(.green)
                    Text("Masuki lahan ngahuma").font(.title.bold())
                    Text("Masuki lahan 360° yang mengelilingi Anda. Menoleh untuk menjelajah, lalu alami perubahan dari vegetasi kering hingga tunas baru.")
                        .multilineTextAlignment(.center)
                    if permissionChecked {
                        Text("AR memerlukan perangkat yang mendukung dan izin kamera.").font(.caption)
                        Button("Buka Pengaturan") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        Button("Coba pratinjau 3D") { preview = true }.buttonStyle(.borderedProminent)
                    } else { ProgressView().tint(.white) }
                }.padding(28).foregroundStyle(.white)
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                VStack(alignment: .leading) {
                    Text("NGAHUMA").font(.headline)
                    Text(preview ? "Pratinjau 360° · Geser untuk melihat" : "Lingkungan 360° · Menoleh untuk melihat").font(.caption)
                }
                Spacer()
                Button { scene.muted.toggle() } label: {
                    Image(systemName: scene.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }.accessibilityLabel(scene.muted ? "Aktifkan suara" : "Matikan suara")
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Tutup ngahuma").padding(.leading, 12)
            }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal)
        }
        .safeAreaInset(edge: .bottom) {
            if cameraReady || preview {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(scene.title).font(.title3.bold())
                        Spacer()
                        Text("\(min(scene.stage.rawValue + 1, 6))/6").font(.caption.monospacedDigit())
                    }
                    if scene.loadingAssets {
                        ProgressView("Memuat lingkungan…")
                    } else if let error = scene.assetError {
                        Text(error).font(.subheadline)
                        Button("Coba lagi") { Task { await scene.prepareAssets() } }
                    } else {
                        Text(scene.instruction).font(.subheadline)
                    }
                    if !scene.tracking.isEmpty { Text(scene.tracking).font(.caption).foregroundStyle(.secondary) }
                    if scene.stage == .burning {
                        ProgressView(value: scene.progress).tint(.orange)
                        Button("Akhiri adegan api") { scene.finishBurn() }.buttonStyle(.bordered)
                    }
                    if scene.stage == .prepared {
                        Button("Mulai pembakaran virtual", systemImage: "flame.fill") { scene.ignite() }
                            .buttonStyle(.borderedProminent).tint(.orange)
                    }
                    HStack {
                        Text("Adegan ilustratif · bukan panduan praktik adat").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Ulangi") { scene.reset() }.font(.caption.bold())
                    }
                }.padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)).padding()
            }
        }
        .task {
            if ARWorldTrackingConfiguration.isSupported {
                if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                }
                guard !Task.isCancelled else { return }
                cameraReady = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            }
            permissionChecked = true
        }
        .onDisappear { scene.stop() }
        .onChange(of: phase) { _, value in
            if value == .background { scene.stop(); dismiss() }
        }
    }
}

private struct NgahumaCamera: UIViewRepresentable {
    let scene: NgahumaScene
    let preview: Bool
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: preview ? .nonAR : .ar, automaticallyConfigureSession: false)
        scene.attach(view, preview: preview)
        return view
    }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
