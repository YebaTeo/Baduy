import SwiftUI
import AVKit

struct HomeView: View {
    @ObservedObject var app: AppState
    let active: Bool
    @StateObject private var feed: FeedState
    @ViewState private var visible: UUID?
    @ViewState private var uploading = false
    @ViewState private var account = false
    init(app: AppState, active: Bool) {
        self.app = app; self.active = active
        _feed = StateObject(wrappedValue: FeedState(repository: app.repository))
    }
    var body: some View {
        NavigationStack {
            Group {
                if feed.posts.isEmpty && feed.loading { ProgressView("Finding experiences…") }
                else if feed.posts.isEmpty {
                    ContentUnavailableView {
                        Label(feed.error == nil ? "A place for your experiences" : "Couldn’t load the feed", systemImage: "photo.on.rectangle")
                    } description: {
                        Text(feed.error ?? "Approved photos and videos will appear here. Share an experience to get started.")
                    } actions: { Button("Try again") { Task { await feed.load(reset: true) } } }
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(feed.posts) { post in
                                PostCard(post: post, app: app, active: active && !uploading && !account && visible == post.id,
                                    voting: feed.pendingVotes.contains(post.id)) { direction in
                                    Task { await feed.vote(post, direction: direction) }
                                }
                                .containerRelativeFrame(.vertical)
                                .id(post.id)
                                .task {
                                    if post.id == feed.posts.last?.id { await feed.load() }
                                }
                            }
                        }.scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $visible)
                    .scrollIndicators(.hidden)
                    .refreshable { await feed.load(reset: true) }
                    .overlay(alignment: .top) {
                        if let error = feed.error {
                            Button { Task { await feed.load() } } label: { Label(error, systemImage: "arrow.clockwise").font(.caption).padding().background(.regularMaterial) }
                        }
                    }
                }
            }
            .navigationTitle("Experiences").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Account", systemImage: "person.crop.circle") { account = true } }
                ToolbarItem(placement: .topBarTrailing) { Button("Share experience", systemImage: "plus") { uploading = true } }
            }
            .sheet(isPresented: $uploading, onDismiss: { Task { await feed.load(reset: true) } }) { UploadView(app: app) }
            .sheet(isPresented: $account) { AccountView(app: app) }
            .task { if feed.posts.isEmpty { await feed.load(); visible = feed.posts.first?.id } }
        }
    }
}
struct MediaView: View {
    let post: Post
    let api: API
    let active: Bool
    @Environment(\.scenePhase) private var phase
    @ViewState private var url: URL?
    @ViewState private var player: AVPlayer?
    @ViewState private var error: String?
    var body: some View {
        Group {
            if let player { VideoPlayer(player: player) }
            else if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    case .failure: ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark", description: Text("Check your connection and return to this post to retry."))
                    default: ProgressView()
                    }
                }
            } else if let error { ContentUnavailableView("Media unavailable", systemImage: "wifi.exclamationmark", description: Text(error)) }
            else if post.media_type == "video" && !active { Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.secondary) }
            else { ProgressView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(post.media_type == "video" ? "Video experience" : "Photo: \(post.caption)")
        .task(id: active) {
            player?.pause(); player = nil
            do {
                if post.media_type == "video" {
                    if active {
                        let signed = try await api.signedURL(post.storage_path)
                        try Task.checkCancellation()
                        let created = AVPlayer(url: signed); player = created
                        if phase == .active { created.play() }
                    } else if let path = post.thumbnail_path { url = try await api.signedURL(path) }
                } else { url = try await api.signedURL(post.storage_path) }
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
        .onChange(of: phase) { _, value in if value == .active && active { player?.play() } else { player?.pause() } }
        .onDisappear { player?.pause(); player = nil }
    }
}
struct PostCard: View {
    let post: Post
    @ObservedObject var app: AppState
    let active: Bool
    var voting = false
    var onVote: ((Int) -> Void)?
    @ViewState private var showProfile = false
    @ViewState private var reporting = false
    @ViewState private var showLocation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MediaView(post: post, api: app.api, active: active && !showProfile && !reporting && !showLocation)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .layoutPriority(-1)
            HStack {
                Button("@\(post.username ?? "visitor")") { showProfile = true }.font(.headline)
                Spacer()
                Menu {
                    Button("Report content", systemImage: "flag") { reporting = true }
                    if post.author_id == app.profile?.id {
                        Button("Delete my post", role: .destructive) { reporting = true }
                    }
                } label: { Label("Post actions", systemImage: "ellipsis.circle").labelStyle(.iconOnly).frame(width: 44, height: 44) }
            }
            if !post.caption.isEmpty { Text(post.caption).lineLimit(3) }
            Text(post.categories.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            HStack {
                voteButton("Upvote", symbol: "arrow.up", count: post.upvotes, direction: 1)
                voteButton("Downvote", symbol: "arrow.down", count: post.downvotes, direction: -1)
                Spacer()
                if post.coordinate != nil {
                    Button { showLocation = true } label: { Label(post.location_name ?? "Approximate location", systemImage: "mappin.and.ellipse").font(.caption) }
                }
            }
            Text(String(post.created_at.prefix(10))).font(.caption2).foregroundStyle(.secondary)
        }.padding()
        .sheet(isPresented: $showProfile) { CreatorView(id: post.author_id, repository: app.repository) }
        .sheet(isPresented: $reporting) { ReportView(post: post, app: app) }
        .sheet(isPresented: $showLocation) { PostLocationView(post: post) }
    }
    private func voteButton(_ label: String, symbol: String, count: Int, direction: Int) -> some View {
        Button { onVote?(direction) } label: { Label("\(count)", systemImage: symbol).frame(minWidth: 44, minHeight: 44) }
            .tint(post.my_vote == direction ? .accentColor : .secondary)
            .disabled(voting || onVote == nil)
            .accessibilityLabel("\(label), \(count)")
            .accessibilityValue(post.my_vote == direction ? "Selected" : "Not selected")
    }
}
struct PostDetailView: View {
    @ObservedObject var app: AppState
    @ViewState private var post: Post
    @ViewState private var voting = false
    init(post: Post, app: AppState) { self.app = app; _post = State(initialValue: post) }
    var body: some View {
        PostCard(post: post, app: app, active: true, voting: voting) { direction in
            Task {
                guard !voting else { return }; voting = true
                let previous = post; let value = post.my_vote == direction ? 0 : direction
                post.setVote(value)
                defer { voting = false }
                do { try await app.repository.vote(post: post.id, value: value) }
                catch { post = previous; app.error = error.localizedDescription }
            }
        }.navigationTitle("Experience").navigationBarTitleDisplayMode(.inline)
    }
}
struct CreatorView: View {
    let id: UUID
    let repository: SupabaseRepository
    @ViewState private var profile: Profile?
    @ViewState private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 64)).foregroundStyle(.secondary)
                        Text(profile.display_name ?? "Visitor").font(.title2)
                        Text("@\(profile.username ?? "visitor")")
                    }
                } else if let error { ContentUnavailableView("Profile unavailable", systemImage: "person", description: Text(error)) }
                else { ProgressView() }
            }.navigationTitle("Profile").toolbar { CloseButton() }
        }.presentationDetents([.medium, .large])
        .task { do { profile = try await repository.profile(id) } catch { self.error = error.localizedDescription } }
    }
}
struct CloseButton: ToolbarContent {
    @Environment(\.dismiss) private var dismiss
    var body: some ToolbarContent { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
}
struct AccountView: View {
    @ObservedObject var app: AppState
    @ViewState private var deleting = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Your profile") {
                    Text("@\(app.profile?.username ?? "visitor")")
                    NavigationLink("My experiences") { MyPostsView(app: app) }
                }
                Section("Respectful visits") { Text(app.guidance) }
                Section {
                    Button("Sign out") { Task { await app.logout() } }
                    Button("Delete account", role: .destructive) { deleting = true }
                }.disabled(app.busy)
            }.navigationTitle("Account").toolbar { CloseButton() }
            .confirmationDialog("Permanently delete your account and all your posts?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { Task { await app.deleteAccount() } }
            }
        }
    }
}
struct ReportView: View {
    let post: Post
    @ObservedObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ViewState private var reason = ""
    @ViewState private var busy = false
    @ViewState private var error: String?
    @ViewState private var deleting = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Tell our moderators what needs review") { TextField("Reason", text: $reason, axis: .vertical).lineLimit(3...8) }
                Button("Submit report") {
                    Task {
                        busy = true; defer { busy = false }
                        do { try await app.repository.report(post.id, reason: reason); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(reason.count < 3 || reason.count > 1000 || busy)
                if post.author_id == app.profile?.id {
                    Button("Delete this post", role: .destructive) { deleting = true }.disabled(busy)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Content review").toolbar { CloseButton() }
            .confirmationDialog("Delete this post permanently?", isPresented: $deleting) {
                Button("Delete post", role: .destructive) {
                    Task {
                        busy = true; defer { busy = false }
                        do { try await app.repository.remove(post); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
}
