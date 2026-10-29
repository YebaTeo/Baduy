import Foundation
import AuthenticationServices
import Combine

@MainActor final class AppState: ObservableObject {
    let api: API
    let repository: SupabaseRepository
    @Published var profile: Profile?
    @Published var restoring = true
    @Published var signedIn = false
    @Published var recoveryReady = false
    private var pendingURL: URL?
    @Published var busy = false
    @Published var error: String?
    @Published var notice: String?
    @Published var guidance = "Ask permission before photographing people or places. Follow locally communicated rules. Do not share sensitive locations."
    init(api: API = API()) { self.api = api; repository = SupabaseRepository(api: api) }
    func restore() async {
        do {
            if try await api.restore() {
                if let flow = try SecureStore.readFlow(), flow.isValid, flow.completed, flow.kind == .recovery { recoveryReady = true }
                else { try await loadProfile() }
            }
        } catch { self.error = error.localizedDescription }
        restoring = false
        if let url = pendingURL { pendingURL = nil; await handleEmailLink(url) }
    }
    func loadProfile() async throws {
        profile = try await repository.profile(api.userID())
        signedIn = true
        struct Guidance: Decodable { let message: String }
        if let result = try? await api.decode([Guidance].self, path: "rest/v1/community_guidance?select=message&id=eq.1"), let message = result.first?.message { guidance = message }
    }
    func login(username: String, password: String) async {
        await perform {
            let data = try await self.api.request("functions/v1/username-login", method: "POST", body: ["username": username, "password": password], authenticated: false)
            try await self.api.accept(data)
            try await self.loadProfile()
        }
    }
    func signup(username: String, email: String, password: String) async {
        await perform {
            let flow = PendingEmailFlow(verifier: try SecureStore.nonce(), email: email.trimmingCharacters(in: .whitespacesAndNewlines), kind: .confirmation, createdAt: Date())
            try SecureStore.saveFlow(flow)
            let data = try await self.api.request("auth/v1/signup?redirect_to=baduy%3A%2F%2Fauth%2Fconfirmation", method: "POST", body: ["email": flow.email, "password": password, "data": ["username": username.lowercased()], "code_challenge": SecureStore.challenge(flow.verifier), "code_challenge_method": "s256"], authenticated: false)
            if (try? JSONDecoder().decode(AuthSession.self, from: data)) != nil {
                try await self.api.accept(data); SecureStore.clearFlow(); try await self.loadProfile()
            } else { self.notice = "Open the confirmation link from your email on this device to return to Kanekes. If testing in Simulator, open the link inside Simulator." }
        }
    }
    func apple(_ result: Result<ASAuthorization, Error>, nonce: String?) async {
        if case .failure(let error) = result, (error as? ASAuthorizationError)?.code == .canceled { return }
        await perform {
            guard let nonce, case .success(let auth) = result,
                  let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
                  let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) else { throw AppError.authentication }
            let data = try await self.api.request("functions/v1/apple-login", method: "POST", body: ["id_token": token, "nonce": nonce, "code": code], authenticated: false)
            try await self.api.accept(data); try await self.loadProfile()
        }
    }
    func chooseUsername(_ value: String) async {
        await perform {
            let id = try await self.api.userID()
            _ = try await self.api.request("rest/v1/profiles?id=eq.\(id)", method: "PATCH", body: ["username": value.lowercased()])
            try await self.loadProfile()
        }
    }
    func logout() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { _ = try await api.request("auth/v1/logout", method: "POST") }
        catch { notice = "Signed out on this device. The server could not be reached to revoke other sessions." }
        await api.clear(); SecureStore.clearFlow(); recoveryReady = false; profile = nil; signedIn = false
    }
    func deleteAccount() async {
        await perform {
            _ = try await self.api.request("functions/v1/delete-account", method: "POST", body: [:])
            await self.api.clear(); self.profile = nil; self.signedIn = false
        }
    }
    func handleEmailLink(_ url: URL) async {
        guard url.scheme == "baduy", url.host == "auth" else { return }
        if restoring { pendingURL = url; return }
        await perform {
            guard var flow = try SecureStore.readFlow(), flow.isValid,
                  url.path == "/\(flow.kind.rawValue)", !flow.completed,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                  !code.isEmpty, code.count < 2048 else {
                throw AppError.message("This email link is expired or belongs to a different device. Request a new link from this app.")
            }
            let data = try await self.api.request("auth/v1/token?grant_type=pkce", method: "POST", body: ["auth_code": code, "code_verifier": flow.verifier], authenticated: false)
            let session = try JSONDecoder().decode(AuthSession.self, from: data)
            guard session.user.email?.lowercased() == flow.email.lowercased() else { throw AppError.authentication }
            try await self.api.accept(data)
            self.notice = nil
            if flow.kind == .recovery {
                flow.completed = true; try SecureStore.saveFlow(flow)
                self.recoveryReady = true; self.signedIn = false
            } else {
                SecureStore.clearFlow(); try await self.loadProfile()
            }
        }
    }
    func updateRecoveredPassword(_ password: String) async {
        await perform {
            guard self.recoveryReady, password.count >= 12 else { throw AppError.authentication }
            _ = try await self.api.request("auth/v1/user", method: "PUT", body: ["password": password])
            try await self.loadProfile()
            SecureStore.clearFlow(); self.recoveryReady = false
        }
    }
    func perform(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { try await action() } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    static func validUsername(_ value: String) -> Bool {
        value.range(of: "^[a-zA-Z0-9_]{3,24}$", options: .regularExpression) != nil
    }
}

@MainActor final class FeedState: ObservableObject {
    let repository: any ContentRepository
    @Published var posts: [Post] = []
    @Published var loading = false
    @Published var exhausted = false
    @Published var error: String?
    @Published var pendingVotes: Set<UUID> = []
    init(repository: any ContentRepository) { self.repository = repository }
    func load(reset: Bool = false) async {
        guard !loading, reset || !exhausted else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let page = try await repository.feed(after: reset ? nil : posts.last)
            try Task.checkCancellation()
            if reset { posts = [] }
            let existing = Set(posts.map(\.id))
            posts.append(contentsOf: page.filter { !existing.contains($0.id) })
            exhausted = page.count < 15
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func vote(_ post: Post, direction: Int) async {
        guard !pendingVotes.contains(post.id), let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let old = posts[index]
        let value = old.my_vote == direction ? 0 : direction
        posts[index].setVote(value); pendingVotes.insert(post.id)
        defer { pendingVotes.remove(post.id) }
        do { try await repository.vote(post: post.id, value: value) }
        catch {
            if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i] = old }
            self.error = error.localizedDescription
        }
    }
}
