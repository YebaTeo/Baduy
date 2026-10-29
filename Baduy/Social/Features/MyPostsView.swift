import Combine
import SwiftUI

@MainActor final class MyPostsState: ObservableObject {
    @Published var posts: [Post] = []
    @Published var error: String?
    @Published var loading = false
    @Published var exhausted = false
    let api: API
    init(api: API) { self.api = api }
    func load(reset: Bool = false) async {
        guard !loading, reset || !exhausted else { return }
        loading = true; defer { loading = false }
        do {
            var body: [String: Any] = [:]
            if !reset, let last = posts.last { body = ["before_date": last.created_at, "before_id": last.id.uuidString] }
            let page = try await api.decode([Post].self, path: "rest/v1/rpc/my_posts_page", method: "POST", body: body)
            if reset { posts = [] }
            let existing = Set(posts.map(\.id)); posts += page.filter { !existing.contains($0.id) }
            exhausted = page.count < 15; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func edit(_ post: Post, caption: String) async -> Bool {
        do {
            _ = try await api.request("rest/v1/rpc/edit_post", method: "POST", body: ["post_id": post.id.uuidString, "caption_text": caption])
            await load(reset: true); return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
struct MyPostsView: View {
    let app: AppState
    @StateObject private var state: MyPostsState
    @ViewState private var editing: Post?
    init(app: AppState) { self.app = app; _state = StateObject(wrappedValue: MyPostsState(api: app.api)) }
    var body: some View {
        List {
            if state.posts.isEmpty && !state.loading { Text("Your submitted experiences will appear here.").foregroundStyle(.secondary) }
            ForEach(state.posts) { post in
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink { PostDetailView(post: post, app: app) } label: {
                        VStack(alignment: .leading) {
                            Text(post.caption.isEmpty ? "Untitled experience" : post.caption).lineLimit(2)
                            Text(post.status.capitalized).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if post.status != "removed" { Button("Edit caption") { editing = post }.font(.caption) }
                }
            }
            if state.loading { ProgressView() }
            if !state.exhausted { Button("Load more") { Task { await state.load() } }.disabled(state.loading) }
            if let error = state.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("My experiences")
        .refreshable { await state.load(reset: true) }
        .task { await state.load(reset: true) }
        .sheet(item: $editing) { post in EditCaptionView(post: post, state: state) }
    }
}
struct EditCaptionView: View {
    let post: Post
    @ObservedObject var state: MyPostsState
    @ViewState private var caption: String
    @ViewState private var busy = false
    @Environment(\.dismiss) private var dismiss
    init(post: Post, state: MyPostsState) { self.post = post; self.state = state; _caption = ViewState(initialValue: post.caption) }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Caption", text: $caption, axis: .vertical).lineLimit(3...10)
                Text("Edits return your post to the moderation queue.").font(.caption)
                if let error = state.error { Text(error).foregroundStyle(.red) }
                Button("Save for review") {
                    Task { busy = true; if await state.edit(post, caption: caption) { dismiss() }; busy = false }
                }.disabled(busy || caption.count > 2200)
            }.navigationTitle("Edit experience").toolbar { CloseButton() }.interactiveDismissDisabled(busy)
        }
    }
}
