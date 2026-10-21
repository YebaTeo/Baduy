import SwiftUI
import ARKit
import AVFoundation

/// Permission and device checks happen before creating the camera-backed view.
struct ARCharacterRoom: View {
    let initialCharacter: BaduyCharacter
    @State private var cameraReady = false
    @State private var message: String?
    @State private var showSettings = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if cameraReady {
                    ARCharactersView(initialCharacter: initialCharacter)
                } else if let message {
                    ContentUnavailableView {
                        Label("Ruang AR belum tersedia", systemImage: "camera")
                    } description: {
                        Text(message)
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Button { dismiss() } label: {
                Label("Kembali ke peta", systemImage: "xmark")
                    .padding(12).background(.regularMaterial, in: Capsule())
            }.padding()
        }
        .task {
            guard ARWorldTrackingConfiguration.isSupported else {
                message = "Gunakan iPhone atau iPad yang mendukung ARKit. Simulator dapat digunakan untuk menguji analog dan jarak interaksi, tetapi tidak kamera AR."
                return
            }
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            guard !Task.isCancelled else { return }
            cameraReady = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            if !cameraReady {
                message = "Izinkan akses kamera di Pengaturan untuk bertemu Akang dan Teteh di ruang AR."
                showSettings = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Reopening creates a fresh tracking session after returning to the app.
            if phase == .background { dismiss() }
        }
    }
}
