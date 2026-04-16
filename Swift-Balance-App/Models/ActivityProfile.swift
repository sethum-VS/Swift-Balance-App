//
//  ActivityProfile.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-09.
//

import Foundation

/// A configurable activity that the user can select before starting a timer session.
///
/// This model mirrors the Go backend's `domain.ActivityProfile` struct.
/// IDs are server-assigned strings (e.g. "act_1"), not UUIDs.
///
/// JSON structure from the backend:
/// ```json
/// {
///   "id": "act_1",
///   "name": "Deep Work",
///   "category": "toppingUp",
///   "icon_name": "desktopcomputer",
///   "credit_per_hour": 60.0,
///   "created_at": "2026-04-10T...",
///   "updated_at": "2026-04-10T..."
/// }
/// ```
struct ActivityProfile: Codable, Identifiable, Hashable {

    /// Server-assigned string identifier (e.g. "act_1").
    let id: String

    /// User-facing name, e.g. "Deep Work", "Netflix".
    var name: String

    /// Whether this activity earns credit or spends it.
    /// Matches the Go backend's `ActivityCategory` type ("toppingUp" / "consuming").
    var category: AppState

    /// SF Symbol name for the activity icon.
    var iconName: String

    /// Credits earned per hour (optional, set by server).
    var creditPerHour: Double?

    /// Server timestamps (optional, not always needed client-side).
    var createdAt: Date?
    var updatedAt: Date?

    // MARK: - CodingKeys (match Go backend's snake_case JSON)

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case iconName      = "icon_name"
        case creditPerHour = "credit_per_hour"
        case createdAt     = "created_at"
        case updatedAt     = "updated_at"
    }

    // MARK: - Factory Defaults (fallback when server is unreachable)

    /// Built-in Top-Up profiles — used only when the server is offline.
    static let defaultTopUp: [ActivityProfile] = [
        ActivityProfile(id: "act_1", name: "Deep Work",  category: .toppingUp, iconName: "brain.head.profile"),
        ActivityProfile(id: "act_2", name: "Gym",        category: .toppingUp, iconName: "figure.run"),
    ]

    /// Built-in Consume profiles — used only when the server is offline.
    static let defaultConsume: [ActivityProfile] = [
        ActivityProfile(id: "act_3", name: "Social Media", category: .consuming, iconName: "bubble.left.and.bubble.right.fill"),
        ActivityProfile(id: "act_4", name: "Gaming",       category: .consuming, iconName: "gamecontroller.fill"),
    ]

    /// All factory defaults combined.
    static let allDefaults: [ActivityProfile] = defaultTopUp + defaultConsume
}

/// Payload for creating new activities.
/// The backend generates IDs and timestamps, so create calls should not send them.
struct ActivityProfileCreateRequest: Codable {
    var name: String
    var category: AppState
    var iconName: String
    var creditPerHour: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case category
        case iconName = "icon_name"
        case creditPerHour = "credit_per_hour"
    }

    init(from profile: ActivityProfile) {
        self.name = profile.name
        self.category = profile.category
        self.iconName = profile.iconName
        self.creditPerHour = profile.creditPerHour
    }
}
