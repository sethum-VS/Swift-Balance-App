//
//  Swift_Balance_AppApp.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-07.
//

import SwiftUI
import Combine
import FirebaseCore
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct Swift_Balance_AppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    /// Single source of truth — injected into the environment for every child view.
    @StateObject private var webSocketClient: WebSocketClient
    @StateObject private var timeManager: TimeManager
    @StateObject private var authManager = AuthManager()

    /// Monitors scene lifecycle changes to pause/resume the timer appropriately.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let socket = WebSocketClient()
        _webSocketClient = StateObject(wrappedValue: socket)
        _timeManager = StateObject(wrappedValue: TimeManager(wsClient: socket))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    ContentView()
                        .environmentObject(timeManager)
                        .environmentObject(authManager)
                } else {
                    LoginView()
                        .environmentObject(authManager)
                }
            }
            .onChange(of: authManager.isAuthenticated) { isAuthenticated in
                if isAuthenticated {
                    webSocketClient.connect()
                    timeManager.fetchActivities()
                } else {
                    webSocketClient.disconnect(reason: "auth state changed to signed out")
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                timeManager.handleBackgrounded()
            case .inactive:
                break
            case .active:
                timeManager.handleForegrounded()
            default:
                break
            }
        }
    }
}
