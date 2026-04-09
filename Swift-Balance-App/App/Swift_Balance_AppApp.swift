//
//  Swift_Balance_AppApp.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-07.
//

import SwiftUI

@main
struct Swift_Balance_AppApp: App {
    /// Single source of truth — injected into the environment for every child view.
    @StateObject private var timeManager = TimeManager()

    /// Monitors scene lifecycle changes to pause/resume the timer appropriately.
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(timeManager)
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                timeManager.handleBackgrounded()
            case .active:
                timeManager.handleForegrounded()
            default:
                break
            }
        }
    }
}
