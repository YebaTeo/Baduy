import Combine
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import MapKit

struct PickedFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .data) { received in
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: target)
            return PickedFile(url: target)
        }
    }
}
@MainActor final class UploadState: ObservableObject {
    @Published var file: URL?
    @Published var thumbnail: URL?
    @Published var video = false
    @Published var preparing = false
    @Published var uploading = false
    @Published var progress = 0.0
    @Published var error: String?
    @Published var success = false
    @Published var attempted = false
    private var postID = UUID()
    private var uploadedPaths: [String] = []
    let app: AppState
    init(app: AppState) { self.app = app }
    func prepare(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        preparing = true; error = nil
        defer { preparing = false }
        cleanFiles()
        do {
            guard let picked = try await item.loadTransferable(type: PickedFile.self) else { throw AppError.invalidMedia }
            defer { try? FileManager.default.removeItem(at: picked.url) }
            let size = try picked.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 25 * 1024 * 1024 else { throw AppError.invalidMedia }
            video = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(video ? "mp4" : "jpg")
            if video {
                let asset = AVURLAsset(url: picked.url)
                let duration = try await asset.load(.duration).seconds
                guard duration.isFinite, duration > 0, duration <= 60,
                      let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { throw AppError.invalidMedia }
                exporter.metadata = []
                try await exporter.export(to: target, as: .mp4)
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: target))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 640, height: 640)
                let frame = try await generator.image(at: .zero).image
                let thumb = target.deletingPathExtension().appendingPathExtension("jpg")
                guard let bytes = UIImage(cgImage: frame).jpegData(compressionQuality: 0.75) else { throw AppError.invalidMedia }
                try bytes.write(to: thumb); thumbnail = thumb
            } else {
                guard let image = UIImage(contentsOfFile: picked.url.path) else { throw AppError.invalidMedia }
                let ratio = min(1, 2048 / max(image.size.width, image.size.height))
                let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                guard let bytes = resized.jpegData(compressionQuality: 0.85) else { throw AppError.invalidMedia }
                try bytes.write(to: target)
            }
            guard (try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 25 * 1024 * 1024 else { throw AppError.invalidMedia }
            try Task.checkCancellation()
            file = target; postID = UUID(); uploadedPaths = []
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func publish(caption: String, categories: [String], coordinate: CLLocationCoordinate2D?, place: String) async {
        guard let file, !uploading else { return }
        uploading = true; attempted = true; error = nil; progress = 0
        defer { uploading = false }
        do {
            let user = try await app.api.userID().uuidString.lowercased()
            let path = "\(user)/\(postID.uuidString.lowercased()).\(video ? "mp4" : "jpg")"
            let thumbPath = "\(user)/\(postID.uuidString.lowercased())-thumb.jpg"
            if !uploadedPaths.contains(path) {
                do {
                    try await app.api.upload(file, path: path, contentType: video ? "video/mp4" : "image/jpeg") { [weak self] value in
                        Task { @MainActor in self?.progress = value * 0.85 }
                    }
                } catch {
                    guard (try? await app.api.signedURL(path)) != nil else { throw error }
                }
                uploadedPaths.append(path)
            }
            if let thumbnail, !uploadedPaths.contains(thumbPath) {
                do { try await app.api.upload(thumbnail, path: thumbPath, contentType: "image/jpeg") { _ in } }
                catch { guard (try? await app.api.signedURL(thumbPath)) != nil else { throw error } }
                uploadedPaths.append(thumbPath)
            }
            var body: [String: Any] = ["post_id": postID.uuidString, "caption_text": caption, "category_list": categories, "object_path": path, "kind": video ? "video" : "photo"]
            if let coordinate {
                body["lat"] = (coordinate.latitude * 100).rounded() / 100
                body["lon"] = (coordinate.longitude * 100).rounded() / 100
                body["place"] = place.isEmpty ? "Approximate area" : place
            }
            if thumbnail != nil { body["thumb"] = thumbPath }
            _ = try await app.api.request("rest/v1/rpc/publish_post", method: "POST", body: body)
            progress = 1; success = true; uploadedPaths = []; cleanFiles()
        } catch { self.error = "\(error.localizedDescription) You can retry safely; your draft is retained." }
    }
    func discard() async {
        // Check for a committed post before deleting files after an ambiguous network failure.
        if !uploadedPaths.isEmpty {
            struct Row: Decodable { let id: UUID }
            if let rows = try? await app.api.decode([Row].self, path: "rest/v1/posts?id=eq.\(postID)&select=id"), rows.isEmpty {
                try? await app.repository.removeMedia(uploadedPaths)
            }
        }
        cleanFiles()
    }
    func cleanFiles() {
        for url in [file, thumbnail].compactMap({ $0 }) { try? FileManager.default.removeItem(at: url) }
        file = nil; thumbnail = nil
    }
}
struct UploadView: View {
    @ObservedObject var app: AppState
    @StateObject private var state: UploadState
    @Environment(\.dismiss) private var dismiss
    @ViewState private var item: PhotosPickerItem?
    @ViewState private var caption = ""
    @ViewState private var categories: Set<String> = []
    @ViewState private var locationConsent = false
    @ViewState private var coordinate: CLLocationCoordinate2D?
    @ViewState private var place = ""
    @ViewState private var choosingLocation = false
    @ViewState private var rulesConsent = false
    init(app: AppState) { self.app = app; _state = StateObject(wrappedValue: UploadState(app: app)) }
    var body: some View {
        let pickerTitle = state.file == nil ? "Choose media" : "Change media"
        return NavigationStack {
            Form {
                Section("Photo or video") {
                    PhotosPicker(selection: $item, matching: .any(of: [.images, .videos])) {
                        Label(pickerTitle, systemImage: "photo.on.rectangle")
                    }.disabled(state.uploading || state.preparing || state.attempted)
                    if state.preparing { ProgressView("Preparing and removing metadata…") }
                    if let file = state.file {
                        if state.video { Label("Video ready", systemImage: "video") }
                        else if let image = UIImage(contentsOfFile: file.path) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180) }
                    }
                    Text("Photos and videos up to 25 MB. Videos up to 60 seconds.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Your experience") {
                    TextField("Caption", text: $caption, axis: .vertical).lineLimit(3...6)
                    ForEach(["Nature", "Journey", "Culture", "Food", "Reflection"], id: \.self) { category in
                        Toggle(category, isOn: Binding(get: { categories.contains(category) }, set: { if $0 { categories.insert(category) } else { categories.remove(category) } }))
                    }
                }
                Section("Optional location") {
                    Toggle("I consent to share an approximate area", isOn: $locationConsent)
                    if locationConsent {
                        Button(coordinate == nil ? "Choose an area on the map" : "Change selected area") { choosingLocation = true }
                        TextField("Public place name (optional)", text: $place)
                        Text("Coordinates are rounded to roughly a kilometre. Do not select sensitive community locations.").font(.caption)
                    }
                }
                Section("Before sharing") {
                    Text(app.guidance)
                    Toggle("I have permission to share this content", isOn: $rulesConsent)
                    Text("Your post will appear in the feed after moderator approval.").font(.caption).foregroundStyle(.secondary)
                }
                if state.uploading { ProgressView("Uploading…", value: state.progress) }
                if let error = state.error { Text(error).foregroundStyle(.red) }
                Button("Publish for review") {
                    Task { await state.publish(caption: caption, categories: categories.sorted(), coordinate: locationConsent ? coordinate : nil, place: place) }
                }.disabled(state.file == nil || state.preparing || state.uploading || !rulesConsent || caption.count > 2200 || (locationConsent && coordinate == nil))
            }
            .disabled(state.uploading)
            .navigationTitle("Share experience").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { Task { await state.discard(); dismiss() } }.disabled(state.uploading) } }
            .interactiveDismissDisabled()
            .task(id: item) { await state.prepare(item) }
            .sheet(isPresented: $choosingLocation) { LocationPicker(coordinate: $coordinate) }
            .alert("Submitted for review", isPresented: $state.success) { Button("Done") { dismiss() } } message: { Text("Your experience will appear after it has been approved.") }
        }
    }
}
struct LocationPicker: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Environment(\.dismiss) private var dismiss
    @ViewState private var center: CLLocationCoordinate2D
    @ViewState private var position: MapCameraPosition

    // A local browsing window, not an administrative village boundary.
    private static let villageRegion = MKCoordinateRegion(
        center: .init(latitude: -6.614, longitude: 106.226),
        span: .init(latitudeDelta: 0.055, longitudeDelta: 0.045)
    )
    private static let browsingRegion = MKCoordinateRegion(
        center: villageRegion.center,
        span: .init(latitudeDelta: 0.075, longitudeDelta: 0.070)
    )
    private static func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && abs(coordinate.latitude - browsingRegion.center.latitude) <= browsingRegion.span.latitudeDelta / 2
            && abs(coordinate.longitude - browsingRegion.center.longitude) <= browsingRegion.span.longitudeDelta / 2
    }
    init(coordinate: Binding<CLLocationCoordinate2D?>) {
        _coordinate = coordinate
        let existing = coordinate.wrappedValue.flatMap { Self.contains($0) ? $0 : nil }
        let start = existing ?? Self.villageRegion.center
        _center = State(initialValue: start)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: start, span: Self.villageRegion.span)))
    }
    var body: some View {
        NavigationStack {
            Map(position: $position,
                bounds: MapCameraBounds(centerCoordinateBounds: Self.browsingRegion,
                                        minimumDistance: 700, maximumDistance: 10_000),
                interactionModes: [.pan, .zoom]) {
                ForEach(MapLandmark.baduyPoints) { landmark in
                    Annotation(landmark.name, coordinate: landmark.coordinate) {
                        Image(systemName: "house.fill")
                            .font(.caption).foregroundStyle(.white)
                            .padding(7).background(.green, in: Circle())
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .onMapCameraChange(frequency: .continuous) { center = $0.region.center }
            .overlay {
                Image(systemName: "plus.circle.fill")
                    .font(.largeTitle).foregroundStyle(.white, .blue)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Selected area at map center")
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Text("Move the map to place your experience under the blue cross.")
                        .font(.subheadline).multilineTextAlignment(.center)
                    Button("Show all Kanekes", systemImage: "arrow.up.left.and.arrow.down.right") {
                        position = .region(Self.villageRegion)
                    }
                    Text("Kanekes & Ciboleger · Only an approximate area will be shared.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding().frame(maxWidth: .infinity).background(.regularMaterial)
            }
            .navigationTitle("Choose area in Kanekes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use area") { coordinate = center; dismiss() }
                        .disabled(!Self.contains(center))
                }
            }
        }
    }
}
