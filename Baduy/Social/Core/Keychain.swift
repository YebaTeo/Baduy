import Foundation
import Security
import CryptoKit

enum SecureStore {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Baduy.session", kSecAttrAccount as String: "supabase"]
    static func read() throws -> AuthSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AppError.keychain }
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }
    static func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AppError.keychain }
        } else if status != errSecSuccess { throw AppError.keychain }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
    static func nonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AppError.keychain }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}


struct PendingEmailFlow: Codable {
    enum Kind: String, Codable { case confirmation, recovery }
    let verifier: String
    let email: String
    let kind: Kind
    let createdAt: Date
    var completed = false
    var isValid: Bool { Date().timeIntervalSince(createdAt) < 3600 }
    var redirect: String { "baduy://auth/\(kind.rawValue)" }
}
extension SecureStore {
    private static var flowQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Baduy.email-flow", kSecAttrAccount as String: "pkce"]
    }
    static func saveFlow(_ value: PendingEmailFlow) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(flowQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = flowQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AppError.keychain }
        } else if status != errSecSuccess { throw AppError.keychain }
    }
    static func readFlow() throws -> PendingEmailFlow? {
        var query = flowQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw AppError.keychain }
        return try JSONDecoder().decode(PendingEmailFlow.self, from: data)
    }
    static func clearFlow() { SecItemDelete(flowQuery as CFDictionary) }
    static func challenge(_ value: String) -> String {
        Data(SHA256.hash(data: Data(value.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
