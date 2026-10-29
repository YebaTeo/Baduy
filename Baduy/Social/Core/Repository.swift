import Foundation
import MapKit

protocol ContentRepository: Sendable {
    func feed(after: Post?) async throws -> [Post]
    func vote(post: UUID, value: Int) async throws
    func guides() async throws -> [Guide]
    func map(region: MKCoordinateRegion) async throws -> [Post]
}
struct SupabaseRepository: ContentRepository {
    let api: API
    func feed(after: Post?) async throws -> [Post] {
        var body: [String: Any] = [:]
        if let after { body = ["before_date": after.created_at, "before_id": after.id.uuidString] }
        return try await api.decode([Post].self, path: "rest/v1/rpc/feed_page", method: "POST", body: body)
    }
    func vote(post: UUID, value: Int) async throws {
        let user = try await api.userID()
        if value == 0 {
            _ = try await api.request("rest/v1/votes?post_id=eq.\(post)&user_id=eq.\(user)", method: "DELETE")
        } else {
            _ = try await api.request("rest/v1/votes?on_conflict=user_id,post_id", method: "POST",
                body: ["user_id": user.uuidString, "post_id": post.uuidString, "vote_type": value], prefer: "resolution=merge-duplicates")
        }
    }
    func guides() async throws -> [Guide] { try await api.decode([Guide].self, path: "rest/v1/tour_guides?select=*&order=name") }
    func map(region: MKCoordinateRegion) async throws -> [Post] {
        let south = max(-90, region.center.latitude - region.span.latitudeDelta / 2)
        let north = min(90, region.center.latitude + region.span.latitudeDelta / 2)
        let west = max(-180, region.center.longitude - region.span.longitudeDelta / 2)
        let east = min(180, region.center.longitude + region.span.longitudeDelta / 2)
        return try await api.decode([Post].self, path: "rest/v1/rpc/map_posts", method: "POST",
            body: ["south": south, "north": north, "west": west, "east": east])
    }
    func profile(_ id: UUID) async throws -> Profile {
        let profiles = try await api.decode([Profile].self, path: "rest/v1/profiles?id=eq.\(id)&select=id,username,display_name")
        guard let value = profiles.first else { throw AppError.server }; return value
    }
    func report(_ post: UUID, reason: String) async throws {
        _ = try await api.request("rest/v1/reports", method: "POST", body: ["reporter_id": try await api.userID().uuidString, "post_id": post.uuidString, "reason": reason])
    }
    func remove(_ post: Post) async throws {
        _ = try await api.request("rest/v1/posts?id=eq.\(post.id)", method: "DELETE")
        try await removeMedia([post.storage_path, post.thumbnail_path].compactMap { $0 })
    }
    func removeMedia(_ paths: [String]) async throws {
        _ = try await api.request("storage/v1/object/post-media", method: "DELETE", body: ["prefixes": paths])
    }
}
