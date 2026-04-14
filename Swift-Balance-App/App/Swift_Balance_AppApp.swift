//
//  Swift_Balance_AppApp.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-07.
//

import SwiftUI
import Combine
import FirebaseCore

@main
struct Swift_Balance_AppApp: App {
    /// Single source of truth — injected into the environment for every child view.
    @StateObject private var timeManager = TimeManager()
    @StateObject private var authManager = AuthManager()

    /// Monitors scene lifecycle changes to pause/resume the timer appropriately.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ContentView()
                    .environmentObject(timeManager)
                    .environmentObject(authManager)
            } else {
                LoginView()
                    .environmentObject(authManager)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background, .inactive:
                timeManager.handleBackgrounded()
            case .active:
                timeManager.handleForegrounded()
            default:
                break
            }
        }
    }
}
