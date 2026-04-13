//
//  Config.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-12.
//

import Foundation

/// Environment Configuration Manager.
///
/// Flip `isProduction` to switch every network call in the app
/// between localhost (development) and cloud (production).
///
/// Usage:
///   - `Config.apiBaseURL`  → used by `APIConfig` for REST endpoints
///   - `Config.wsBaseURL`   → used by `WebSocketClient` for real-time sync
enum Config {

    // ┌──────────────────────────────────────────────┐
    // │  FLIP THIS TO SWITCH ENVIRONMENTS            │
    // └──────────────────────────────────────────────┘
    static let isProduction = true

    // MARK: - Development (localhost)

    private static let devAPIBase = "http://localhost:3000"
    private static let devWSBase  = "ws://localhost:3000/ws"

    // MARK: - Production (Cloud Run)

    private static let prodAPIBase = "https://balance-web-1047596610069.us-central1.run.app"
    private static let prodWSBase  = "wss://balance-web-1047596610069.us-central1.run.app/ws"

    // MARK: - Computed Endpoints

    /// Base URL for all REST API calls.
    static var apiBaseURL: String {
        isProduction ? prodAPIBase : devAPIBase
    }

    /// Full WebSocket URL for real-time sync.
    static var wsBaseURL: String {
        isProduction ? prodWSBase : devWSBase
    }
}
