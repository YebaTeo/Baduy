import Foundation
import MapKit

actor TestRepository: ContentRepository {
    var pages: [[Post]]
    var cursors: [UUID?] = []
    var votes: [Int] = []
    var failVotes = false
    var failFeed = false
    init(pages: [[Post]]) { self.pages = pages }
    func feed(after: Post?) async throws -> [Post] {
        cursors.append(after?.id)
        if failFeed { throw AppError.server }
        return pages.isEmpty ? [] : pages.removeFirst()
    }
    func vote(post: UUID, value: Int) async throws {
        votes.append(value)
        try await Task.sleep(for: .milliseconds(15))
        if failVotes { throw AppError.server }
    }
    func guides() async throws -> [Guide] { [] }
    func map(region: MKCoordinateRegion) async throws -> [Post] { [] }
    func rejectVotes() { failVotes = true }
    func rejectFeed() { failFeed = true }
}
func fixture(_ id: UUID = UUID()) -> Post {
    Post(id: id, author_id: UUID(), username: "test_visitor", caption: "Fixture", categories: ["Nature"],
         created_at: "2026-10-27T00:00:00Z", latitude: nil, longitude: nil, location_name: nil,
         location_precision: "none", storage_path: "fixture.jpg", media_type: "photo", thumbnail_path: nil,
         upvotes: 4, downvotes: 2, my_vote: 0)
}
@main struct CoreTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { fatalError("FAIL: \(name)") }
            checks += 1; print("PASS: \(name)")
        }
        var post = fixture()
        post.setVote(1)
        check(post.upvotes == 5 && post.downvotes == 2 && post.my_vote == 1, "upvote")
        post.setVote(-1)
        check(post.upvotes == 4 && post.downvotes == 3 && post.my_vote == -1, "switch vote")
        post.setVote(0)
        check(post.upvotes == 4 && post.downvotes == 2 && post.my_vote == 0, "remove vote")
        let first = (0..<15).map { _ in fixture() }
        let extra = fixture()
        let repository = TestRepository(pages: [first, [first.last!, extra]])
        let feed = FeedState(repository: repository)
        await feed.load()
        check(feed.posts.count == 15 && !feed.exhausted, "first full page")
        await feed.load()
        check(feed.posts.count == 16 && feed.exhausted, "pagination deduplicates overlap")
        let cursors = await repository.cursors
        check(cursors.count == 2 && cursors[0] == nil && cursors[1] == first.last?.id, "keyset cursor uses last post")
        await feed.load()
        let count = await repository.cursors.count
        check(count == 2, "exhausted feed avoids extra request")
        await feed.vote(first[0], direction: 1)
        check(feed.posts[0].my_vote == 1, "vote persisted in presentation")
        await feed.vote(feed.posts[0], direction: 1)
        check(feed.posts[0].my_vote == 0, "tapping selected vote removes it")
        await repository.rejectVotes()
        await feed.vote(feed.posts[0], direction: -1)
        check(feed.posts[0].my_vote == 0 && feed.posts[0].downvotes == 2 && feed.error != nil, "failed vote rolls back")
        check(feed.pendingVotes.isEmpty, "failed vote releases interaction lock")
        await repository.rejectFeed()
        await feed.load(reset: true)
        check(feed.posts.count == 16 && feed.error != nil && !feed.loading, "failed refresh preserves loaded posts")
        check(AppState.validUsername("Visitor_12") && !AppState.validUsername("a") && !AppState.validUsername("name@email"), "username validation")
        let nonce = try SecureStore.nonce()
        check(nonce.count == 64 && SecureStore.hash(nonce).count == 64, "secure Apple nonce format")
        check(SecureStore.hash("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "Apple nonce SHA256 vector")
        let decoded = try JSONDecoder().decode(Post.self, from: JSONEncoder().encode(post))
        check(decoded.id == post.id && decoded.coordinate == nil, "post coding and optional location")
        let rawSession = Data("""
        {"access_token":"fixture","refresh_token":"fixture","expires_in":3600,"user":{"id":"10000000-0000-0000-0000-000000000001"}}
        """.utf8)
        let session = try JSONDecoder().decode(AuthSession.self, from: rawSession)
        check((session.expires_at ?? 0) > Date().timeIntervalSince1970 + 3500, "REST expires_in normalized for refresh")
        let saved = try JSONDecoder().decode(AuthSession.self, from: JSONEncoder().encode(session))
        check(saved.expires_at == session.expires_at, "session expiry preserved across persistence")
        check(SecureStore.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "PKCE RFC 7636 challenge vector")
        let flow = PendingEmailFlow(verifier: "fixture", email: "fixture@example.invalid", kind: .recovery, createdAt: Date())
        check(flow.redirect == "baduy://auth/recovery" && flow.isValid, "recovery callback and expiry")
        let oldFlow = PendingEmailFlow(verifier: "fixture", email: "fixture@example.invalid", kind: .confirmation, createdAt: Date(timeIntervalSinceNow: -7200))
        check(!oldFlow.isValid, "expired email flows rejected")
        let restoredFlow = try JSONDecoder().decode(PendingEmailFlow.self, from: JSONEncoder().encode(flow))
        check(restoredFlow.email == flow.email && restoredFlow.verifier == flow.verifier && !restoredFlow.completed, "email flow persists without losing binding")
        print("\(checks) checks passed")
    }
}
