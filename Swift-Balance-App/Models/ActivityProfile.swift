//
//  ActivityProfile.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-09.
//

import Foundation

/// A configurable activity that the user can select before starting a timer session.
///
/// Profiles are grouped by category (`.toppingUp` or `.consuming`) and displayed
/// in the pre-session activity picker sheet.
struct ActivityProfile: Codable, Identifiable, Hashable {

    /// Unique identifier.
    let id: UUID

    /// User-facing name, e.g. "Deep Work", "Netflix".
    var name: String

    /// Whether this activity earns credit or spends it.
    var category: AppState

    /// SF Symbol name for the activity icon.
    var iconName: String

    // MARK: - Factory Defaults

    /// Built-in Top-Up profiles shipped with the app.
    static let defaultTopUp: [ActivityProfile] = [
        ActivityProfile(id: UUID(), name: "Deep Work",  category: .toppingUp, iconName: "brain.head.profile"),
        ActivityProfile(id: UUID(), name: "Gym",        category: .toppingUp, iconName: "figure.run"),
        ActivityProfile(id: UUID(), name: "Reading",    category: .toppingUp, iconName: "book.fill"),
        ActivityProfile(id: UUID(), name: "Meditation", category: .toppingUp, iconName: "leaf.fill"),
    ]

    /// Built-in Consume profiles shipped with the app.
    static let defaultConsume: [ActivityProfile] = [
        ActivityProfile(id: UUID(), name: "Social Media", category: .consuming, iconName: "bubble.left.and.bubble.right.fill"),
        ActivityProfile(id: UUID(), name: "Gaming",       category: .consuming, iconName: "gamecontroller.fill"),
        ActivityProfile(id: UUID(), name: "Netflix",      category: .consuming, iconName: "play.tv.fill"),
        ActivityProfile(id: UUID(), name: "YouTube",      category: .consuming, iconName: "play.rectangle.fill"),
    ]

    /// All factory defaults combined.
    static let allDefaults: [ActivityProfile] = defaultTopUp + defaultConsume
}
