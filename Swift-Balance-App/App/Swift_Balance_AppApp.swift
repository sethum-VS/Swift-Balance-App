//
//  Swift_Balance_AppApp.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-07.
//

import SwiftUI
import Combine
import FirebaseCore
import GoogleSignIn
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Firebase is now configured in the App struct init() to avoid race conditions.
        // AppDelegate retained for future Push Notification support.
        return true
    }
}

@main
struct Swift_Balance_AppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    /// Single source of truth — injected into the environment for every child view.
    @StateObject private var webSocketClient: WebSocketClient
    @StateObject private var timeManager: TimeManager
    @StateObject private var authManager: AuthManager

    /// Monitors scene lifecycle changes to pause/resume the timer appropriately.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Configure Firebase BEFORE any @StateObject initializers that depend on Auth.
        // This prevents the "default FirebaseApp must be configured" fatal error.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        let socket = WebSocketClient()
        _webSocketClient = StateObject(wrappedValue: socket)
        _timeManager = StateObject(wrappedValue: TimeManager(wsClient: socket))
        _authManager = StateObject(wrappedValue: AuthManager())
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
                    if !authManager.isOfflineMode {
                        // Authenticated user: connect to backend
                        webSocketClient.connect()
                        timeManager.fetchActivities()
                    } else {
                        // Guest mode: load local defaults only
                        timeManager.fetchActivities()
                    }
                } else {
                    webSocketClient.disconnect(reason: "auth state changed to signed out")
                }
            }
            .onOpenURL { url in
                _ = GIDSignIn.sharedInstance.handle(url)
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
