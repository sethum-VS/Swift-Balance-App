//
//  SessionLog.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-09.
//

import Foundation

/// A record of a single completed timer session.
///
/// `SessionLog` is `Codable` so it can be persisted in UserDefaults and
/// `Identifiable` so it can be used directly in SwiftUI lists.
struct SessionLog: Codable, Identifiable {

    /// Unique identifier for the session.
    let id: UUID

    /// The kind of session that was run.
    let type: AppState

    /// How long the session lasted, in seconds.
    let duration: Int

    /// The wall-clock date/time when the session ended.
    let date: Date

    // MARK: - Computed Helpers

    /// Human-readable duration string (HH:mm:ss).
    var formattedDuration: String {
        let h = duration / 3600
        let m = (duration % 3600) / 60
        let s = duration % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// Short label used in the session log UI.
    var typeLabel: String {
        switch type {
        case .toppingUp:  return "Top-Up"
        case .consuming:  return "Consume"
        case .idle:       return "Idle"
        }
    }
}

// MARK: - AppState Codable conformance

/// Extend AppState with Codable so SessionLog can be archived.
extension AppState: Codable {}
