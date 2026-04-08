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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(timeManager)
        }
    }
}
