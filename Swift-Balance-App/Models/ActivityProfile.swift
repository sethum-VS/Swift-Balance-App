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

}
