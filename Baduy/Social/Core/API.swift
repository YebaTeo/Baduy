import Foundation

actor API {
    private let base: URL?
    private let key: String
    private var session: AuthSession?
    private var refreshing: Task<AuthSession, Error>?
    init(bundle: Bundle = .main) {
        let host = bundle.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String ?? ""
        key = bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String ?? ""
        base = host.contains(".") && !host.contains("$") ? URL(string: "https://\(host)") : nil
    }
    func restore() throws -> Bool { session = try SecureStore.read(); return session != nil }
    func userID() throws -> UUID { guard let session else { throw AppError.authentication }; return session.user.id }
    func accept(_ data: Data) throws {
        let value = try JSONDecoder().decode(AuthSession.self, from: data)
        try SecureStore.save(value)
        session = value
    }
    func clear() { refreshing?.cancel(); refreshing = nil; session = nil; SecureStore.clear() }
    private func token() async throws -> String {
        guard let current = session else { throw AppError.authentication }
        if let expiry = current.expires_at, expiry > Date().timeIntervalSince1970 + 60 { return current.access_token }
        if let refreshing { return try await refreshing.value.access_token }
        let task = Task<AuthSession, Error> {
            let data = try await self.request("auth/v1/token?grant_type=refresh_token", method: "POST",
                body: ["refresh_token": current.refresh_token], authenticated: false)
            return try JSONDecoder().decode(AuthSession.self, from: data)
        }
        refreshing = task
        defer { refreshing = nil }
        let updated = try await task.value
        try Task.checkCancellation()
        guard session != nil else { throw AppError.authentication }
        try SecureStore.save(updated)
        session = updated
        return updated.access_token
    }
    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                 authenticated: Bool = true, prefer: String? = nil) async throws -> Data {
        guard let base, !key.isEmpty, let url = URL(string: path, relativeTo: base.appendingPathComponent("/")) else { throw AppError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "apikey")
        if authenticated { request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if (response as? HTTPURLResponse)?.statusCode == 401 { throw AppError.authentication }
            throw AppError.server
        }
        return data
    }
    func decode<T: Decodable>(_ type: T.Type, path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        try JSONDecoder().decode(type, from: await request(path, method: method, body: body))
    }
    func signedURL(_ path: String, bucket: String = "post-media") async throws -> URL {
        struct Result: Decodable { let signedURL: String }
        let result = try await decode(Result.self, path: "storage/v1/object/sign/\(bucket)/\(path)", method: "POST", body: ["expiresIn": 3600])
        guard let base, let url = URL(string: "storage/v1\(result.signedURL)", relativeTo: base.appendingPathComponent("/")) else { throw AppError.server }
        return url
    }
    func upload(_ file: URL, path: String, contentType: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let base else { throw AppError.configuration }
        var request = URLRequest(url: base.appendingPathComponent("storage/v1/object/post-media/\(path)"))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        let delegate = UploadProgress(progress: progress)
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: file, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AppError.server }
    }
}
final class UploadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        progress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
