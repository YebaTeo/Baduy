import Foundation
import CoreLocation

struct AuthSession: Codable, Sendable {
    struct User: Codable, Sendable { let id: UUID; let email: String? }
    let access_token: String
    let refresh_token: String
    let expires_at: Double?
    let user: User
    private enum CodingKeys: String, CodingKey { case access_token, refresh_token, expires_at, expires_in, user }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        access_token = try values.decode(String.self, forKey: .access_token)
        refresh_token = try values.decode(String.self, forKey: .refresh_token)
        user = try values.decode(User.self, forKey: .user)
        if let expiry = try values.decodeIfPresent(Double.self, forKey: .expires_at) { expires_at = expiry }
        else if let interval = try values.decodeIfPresent(Double.self, forKey: .expires_in) { expires_at = Date().timeIntervalSince1970 + interval }
        else { expires_at = nil }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(access_token, forKey: .access_token)
        try values.encode(refresh_token, forKey: .refresh_token)
        try values.encodeIfPresent(expires_at, forKey: .expires_at)
        try values.encode(user, forKey: .user)
    }
}
struct Profile: Codable, Identifiable, Sendable {
    let id: UUID
    var username: String?
    var display_name: String?
}
struct Post: Codable, Identifiable, Sendable {
    let id: UUID
    let author_id: UUID
    let username: String?
    let caption: String
    let categories: [String]
    let created_at: String
    let latitude: Double?
    let longitude: Double?
    let location_name: String?
    let location_precision: String
    let storage_path: String
    let media_type: String
    let thumbnail_path: String?
    var status: String = "approved"
    var upvotes: Int
    var downvotes: Int
    var my_vote: Int
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    mutating func setVote(_ vote: Int) {
        upvotes += (vote == 1 ? 1 : 0) - (my_vote == 1 ? 1 : 0)
        downvotes += (vote == -1 ? 1 : 0) - (my_vote == -1 ? 1 : 0)
        my_vote = vote
    }
}
struct Guide: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let profile_image_path: String?
    let description: String
    let languages: [String]
    let covered_areas: [String]
    let tour_information: String?
    let price: String?
    let contact_information: String?
}
enum AppError: LocalizedError {
    case configuration, authentication, server, invalidMedia, keychain, message(String)
    var errorDescription: String? {
        switch self {
        case .configuration: "Add your Supabase configuration in Local.xcconfig, then rebuild."
        case .authentication: "Unable to sign in. Check your details or try again later."
        case .server: "The request could not be completed. Please try again."
        case .invalidMedia: "Choose a photo or a video up to 25 MB and 60 seconds."
        case .keychain: "Your session could not be saved securely. Please try again."
        case .message(let message): message
        }
    }
}
