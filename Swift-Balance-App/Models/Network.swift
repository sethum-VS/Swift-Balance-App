//
//  Network.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-10.
//

import Foundation

// MARK: - API Configuration

/// Central configuration for all backend endpoints.
enum APIConfig {
    static let baseURL = "http://localhost:3000"
    static let wsURL   = "ws://localhost:3000/ws"

    // REST endpoints
    static let activitiesURL = "\(baseURL)/api/activities"
    static let timerStartURL = "\(baseURL)/api/timer/start"
    static let timerStopURL  = "\(baseURL)/api/timer/stop"
    static let syncURL       = "\(baseURL)/api/sync"
}

// MARK: - WebSocket Event

/// Mirrors the Go backend `domain.WSEvent` structure.
/// ```json
/// { "type": "TIMER_STARTED", "payload": { ... } }
/// ```
struct WSEvent: Decodable {
    let type: String
    let payload: [String: AnyCodable]
}

/// Known event type constants matching Go's `domain.Event*` constants.
enum WSEventType {
    static let timerStarted   = "TIMER_STARTED"
    static let timerStopped   = "TIMER_STOPPED"
    static let balanceUpdated = "BALANCE_UPDATED"
}

// MARK: - Offline Models

/// Represents a session completed while the device was offline.
struct OfflineSession: Codable, Identifiable {
    var id: UUID = UUID()
    let activityID: String
    let duration: Int
    let creditsEarned: Int
    let startTime: Date
    let timestamp: Date
}

// MARK: - Event Payloads

/// Payload received in a `TIMER_STARTED` WebSocket event.
///
/// Server sends `baseBalance` (total CR at session start) and `startTime`
/// so client can animate both clocks via delta calculation:
/// `globalBalance = baseBalance ± elapsed`
struct TimerStartedPayload {
    let sessionID: String
    let activityID: String
    let activityName: String
    let activityCategory: String   // "toppingUp" or "consuming"
    let startTime: Date
    let baseBalance: Int           // CR pool snapshot at session start

    /// Attempts to parse from the raw AnyCodable payload dictionary.
    init?(from dict: [String: AnyCodable]) {
        guard let sid   = dict["sessionID"]?.value as? String,
              let aid   = dict["activityID"]?.value as? String,
              let aname = dict["activityName"]?.value as? String,
              let acat  = dict["activityCategory"]?.value as? String else {
            return nil
        }
        self.sessionID = sid
        self.activityID = aid
        self.activityName = aname
        self.activityCategory = acat

        // baseBalance from server (may arrive as Double from JSON)
        if let b = dict["baseBalance"]?.value as? Double {
            self.baseBalance = Int(b)
        } else if let b = dict["baseBalance"]?.value as? Int {
            self.baseBalance = b
        } else {
            self.baseBalance = 0
        }

        // startTime may arrive as an ISO-8601 string
        if let timeStr = dict["startTime"]?.value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.startTime = formatter.date(from: timeStr) ?? Date()
        } else {
            self.startTime = Date()
        }
    }
}

/// Payload received in a `TIMER_STOPPED` WebSocket event.
struct TimerStoppedPayload {
    let sessionID: String
    let duration: Int
    let creditsEarned: Int

    init?(from dict: [String: AnyCodable]) {
        guard let sid = dict["sessionID"]?.value as? String else { return nil }
        self.sessionID = sid
        // duration and creditsEarned may come as Double from JSON
        if let d = dict["duration"]?.value as? Double {
            self.duration = Int(d)
        } else if let d = dict["duration"]?.value as? Int {
            self.duration = d
        } else {
            self.duration = 0
        }
        if let c = dict["creditsEarned"]?.value as? Double {
            self.creditsEarned = Int(c)
        } else if let c = dict["creditsEarned"]?.value as? Int {
            self.creditsEarned = c
        } else {
            self.creditsEarned = 0
        }
    }
}

/// Payload received in a `BALANCE_UPDATED` WebSocket event.
struct BalanceUpdatedPayload {
    let balance: Int

    init?(from dict: [String: AnyCodable]) {
        if let b = dict["balance"]?.value as? Double {
            self.balance = Int(b)
        } else if let b = dict["balance"]?.value as? Int {
            self.balance = b
        } else {
            return nil
        }
    }
}

// MARK: - AnyCodable (Type-Erased Codable Wrapper)

/// A type-erased `Codable` value, used to decode the arbitrary `payload`
/// dictionary in `WSEvent` where values can be strings, numbers, or nested objects.
struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal.map { $0.value }
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal
        } else {
            value = NSNull()
        }
    }
}
