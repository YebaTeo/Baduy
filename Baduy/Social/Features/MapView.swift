import Combine
import SwiftUI
import MapKit
import ImageIO

extension MKCoordinateRegion {
    static let kanekes = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -6.60, longitude: 106.25), span: MKCoordinateSpan(latitudeDelta: 0.16, longitudeDelta: 0.16))
}
@MainActor final class MapState: ObservableObject {
    @Published var posts: [Post] = []
    @Published var error: String?
    @Published var loading = false
    @Published var region = MKCoordinateRegion.kanekes
    @Published var revision = 0
    let repository: any ContentRepository
    init(repository: any ContentRepository) { self.repository = repository }
    func load() async {
        let generation = revision
        do {
            try await Task.sleep(for: .milliseconds(350))
            loading = true
            let results = try await repository.map(region: region)
            try Task.checkCancellation()
            if generation == revision { posts = results; error = nil; loading = false }
        } catch is CancellationError {} catch { if generation == revision { self.error = error.localizedDescription; loading = false } }
    }
}
struct ExploreMapView: View {
    @ObservedObject var app: AppState
    @StateObject private var state: MapState
    @ViewState private var selected: Post?
    @ViewState private var cluster: [Post] = []
    init(app: AppState) { self.app = app; _state = StateObject(wrappedValue: MapState(repository: app.repository)) }
    var body: some View {
        NavigationStack {
            ClusterMap(posts: state.posts, api: app.api) { region in
                state.region = region; state.revision += 1
            } select: { selected = $0 } selectCluster: { cluster = $0 }
            .overlay(alignment: .top) {
                VStack {
                    if state.loading { ProgressView("Searching this area…").padding(10).background(.regularMaterial, in: Capsule()) }
                    if let error = state.error {
                        Button { state.revision += 1 } label: { Label(error, systemImage: "arrow.clockwise").padding().background(.regularMaterial) }
                    } else if !state.loading && state.posts.isEmpty {
                        Text("No approved geotagged posts in this area").font(.caption).padding(10).background(.regularMaterial, in: Capsule())
                    }
                }.padding()
            }
            .safeAreaInset(edge: .bottom) { Text("Locations are approximate · Up to 150 recent posts per area").font(.caption).padding(8).frame(maxWidth: .infinity).background(.regularMaterial) }
            .navigationTitle("Explore Kanekes").navigationBarTitleDisplayMode(.inline)
            .task(id: state.revision) { await state.load() }
            .sheet(isPresented: Binding(get: { !cluster.isEmpty }, set: { if !$0 { cluster = [] } })) {
                NavigationStack {
                    List(cluster) { post in
                        NavigationLink { PostDetailView(post: post, app: app) } label: {
                            HStack(spacing: 12) {
                                MediaView(post: post, api: app.api, active: false)
                                    .frame(width: 64, height: 64).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading) {
                                Text("@\(post.username ?? "visitor")").font(.headline)
                                Text(post.caption).lineLimit(2)
                                }
                            }
                        }
                    }.navigationTitle("Experiences in this area").navigationBarTitleDisplayMode(.inline).toolbar { CloseButton() }
                }.presentationDetents([.medium, .large])
            }
            .sheet(item: $selected) { post in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 12) {
                        MediaView(post: post, api: app.api, active: false).frame(height: 180)
                        Text("@\(post.username ?? "visitor")").font(.headline)
                        Text(post.caption).lineLimit(3)
                        Text(post.categories.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        NavigationLink("Open experience") { PostDetailView(post: post, app: app) }
                    }.padding().navigationTitle("Nearby experience").navigationBarTitleDisplayMode(.inline).toolbar { CloseButton() }
                }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
        }
    }
}
final class PostAnnotation: NSObject, MKAnnotation {
    let post: Post
    let coordinate: CLLocationCoordinate2D
    var title: String? { "@\(post.username ?? "visitor")" }
    init(post: Post, coordinate: CLLocationCoordinate2D) { self.post = post; self.coordinate = coordinate }
}
struct ClusterMap: UIViewRepresentable {
    let posts: [Post]
    let api: API
    let changed: (MKCoordinateRegion) -> Void
    let select: (Post) -> Void
    let selectCluster: ([Post]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(); map.delegate = context.coordinator
        map.setRegion(.kanekes, animated: false)
        map.register(PhotoAnnotationView.self, forAnnotationViewWithReuseIdentifier: "post")
        map.register(PhotoAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let snapshot = try? encoder.encode(posts)
        if snapshot != context.coordinator.snapshot {
            context.coordinator.snapshot = snapshot
            map.removeAnnotations(map.annotations.filter { $0 is PostAnnotation || $0 is MKClusterAnnotation })
            map.addAnnotations(posts.compactMap { post in post.coordinate.map { PostAnnotation(post: post, coordinate: $0) } })
        }
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ClusterMap
        var snapshot: Data?
        let thumbnails = NSCache<NSString, UIImage>()
        init(_ parent: ClusterMap) { self.parent = parent }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { parent.changed(mapView.region) }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let members: [Post]
            let reuseID: String
            if let cluster = annotation as? MKClusterAnnotation {
                members = cluster.memberAnnotations.compactMap { ($0 as? PostAnnotation)?.post }
                reuseID = MKMapViewDefaultClusterAnnotationViewReuseIdentifier
            } else if let pin = annotation as? PostAnnotation {
                members = [pin.post]
                reuseID = "post"
            } else { return nil }
            // A stable cover keeps the photo from changing when MapKit reorders members.
            let sorted = members.sorted {
                $0.created_at == $1.created_at ? $0.id.uuidString < $1.id.uuidString : $0.created_at > $1.created_at
            }
            guard let cover = sorted.first,
                  let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID, for: annotation) as? PhotoAnnotationView else { return nil }
            view.clusteringIdentifier = annotation is PostAnnotation ? "experiences" : nil
            view.configure(post: cover, count: members.count, api: parent.api, cache: thumbnails)
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation { parent.selectCluster(cluster.memberAnnotations.compactMap { ($0 as? PostAnnotation)?.post }) }
            else if let annotation = view.annotation as? PostAnnotation { parent.select(annotation.post) }
            if let annotation = view.annotation { mapView.deselectAnnotation(annotation, animated: false) }
        }
    }
}
/// The bottom tip is anchored to the shared approximate coordinate.
@MainActor final class PhotoAnnotationView: MKAnnotationView {
    private let photo = UIImageView()
    private let placeholder = UIImageView()
    private let countLabel = UILabel()
    private let videoBadge = UIImageView(image: UIImage(systemName: "play.fill"))
    private let tip = CAShapeLayer()
    private var imageTask: Task<Void, Never>?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bounds = CGRect(x: 0, y: 0, width: 84, height: 94)
        centerOffset = CGPoint(x: 0, y: -47)
        collisionMode = .rectangle
        displayPriority = .defaultHigh
        canShowCallout = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 3)
        let triangle = UIBezierPath()
        triangle.move(to: CGPoint(x: 32, y: 82))
        triangle.addLine(to: CGPoint(x: 42, y: 94))
        triangle.addLine(to: CGPoint(x: 52, y: 82))
        triangle.close()
        tip.path = triangle.cgPath
        tip.fillColor = UIColor.white.cgColor
        layer.addSublayer(tip)
        photo.frame = CGRect(x: 0, y: 0, width: 84, height: 84)
        photo.backgroundColor = .secondarySystemBackground
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.layer.cornerRadius = 18
        photo.layer.borderColor = UIColor.white.cgColor
        photo.layer.borderWidth = 3
        addSubview(photo)
        placeholder.frame = CGRect(x: 27, y: 27, width: 30, height: 30)
        placeholder.contentMode = .scaleAspectFit
        placeholder.tintColor = .secondaryLabel
        addSubview(placeholder)
        countLabel.frame = CGRect(x: 8, y: 55, width: 50, height: 22)
        countLabel.font = .systemFont(ofSize: 14, weight: .bold)
        countLabel.textColor = .white
        countLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        countLabel.textAlignment = .center
        countLabel.layer.cornerRadius = 7
        countLabel.clipsToBounds = true
        addSubview(countLabel)
        videoBadge.frame = CGRect(x: 59, y: 10, width: 15, height: 15)
        videoBadge.tintColor = .white
        videoBadge.layer.shadowColor = UIColor.black.cgColor
        videoBadge.layer.shadowOpacity = 0.8
        videoBadge.layer.shadowRadius = 2
        videoBadge.layer.shadowOffset = .zero
        addSubview(videoBadge)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        photo.image = nil
    }

    func configure(post: Post, count: Int, api: API, cache: NSCache<NSString, UIImage>) {
        imageTask?.cancel()
        photo.image = nil
        placeholder.image = UIImage(systemName: post.media_type == "video" ? "video.fill" : "photo")
        placeholder.isHidden = false
        countLabel.text = "\(count)"
        countLabel.isHidden = count < 2
        videoBadge.isHidden = post.media_type != "video"
        accessibilityLabel = count > 1 ? "\(count) experiences in this area" : "Experience by \(post.username ?? "visitor"). \(post.caption)"
        accessibilityHint = "Opens content at this approximate location"
        // Videos use their still thumbnail; map previews never start playback.
        guard let path = post.thumbnail_path ?? (post.media_type == "video" ? nil : post.storage_path) else { return }
        if let image = cache.object(forKey: path as NSString) {
            photo.image = image
            placeholder.isHidden = true
            return
        }
        imageTask = Task { [weak self] in
            do {
                let url = try await api.signedURL(path)
                try Task.checkCancellation()
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return }
                try Task.checkCancellation()
                // Decode only a pin-sized image, even when the source is a full photo.
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 252
                      ] as CFDictionary) else { return }
                let image = UIImage(cgImage: cgImage)
                cache.countLimit = 150
                cache.setObject(image, forKey: path as NSString)
                self?.photo.image = image
                self?.placeholder.isHidden = true
            } catch { /* Keep the accessible placeholder when offline or cancelled. */ }
        }
    }
}
struct PostLocationView: View {
    let post: Post
    var body: some View {
        NavigationStack {
            if let coordinate = post.coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05)))) {
                    MapCircle(center: coordinate, radius: 1200).foregroundStyle(.blue.opacity(0.2))
                    Marker(post.location_name ?? "Approximate area", coordinate: coordinate)
                }.safeAreaInset(edge: .bottom) { Text("Shared as an approximate area").padding().background(.regularMaterial) }
                .navigationTitle("Location").navigationBarTitleDisplayMode(.inline).toolbar { CloseButton() }
            }
        }.presentationDetents([.medium, .large])
    }
}
