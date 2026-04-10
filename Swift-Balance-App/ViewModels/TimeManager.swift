//
//  TimeManager.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-08.
//

import Foundation
import Combine
import UIKit
import UserNotifications

/// The core ViewModel that drives the Balance app's timer engine.
///
/// **Cloud-Synced Architecture (Sprint 4):**
/// - Button taps fire REST API calls to the Go backend.
/// - Local `@Published` state is updated **only** by incoming WebSocket events.
/// - A local Combine timer ticks the UI display between WS broadcasts.
/// - This guarantees the iOS app, web dashboard, and any other client
///   stay perfectly in sync via the server as the single source of truth.
final class TimeManager: ObservableObject {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let timeBalance       = "balance_timeBalance"
        static let sessionLogs       = "balance_sessionLogs"
    }

    // MARK: - Published State

    /// The current operational state of the app.
    @Published var currentState: AppState = .idle

    /// Total accumulated credit in seconds — synced from server via BALANCE_UPDATED.
    @Published var timeBalance: Int {
        didSet { UserDefaults.standard.set(timeBalance, forKey: Keys.timeBalance) }
    }

    /// Elapsed (top-up) or remaining (consume) seconds for the running session.
    @Published var currentSessionTime: Int = 0

    /// Set to true when the user taps Consume with a zero balance; triggers an alert in the UI.
    @Published var showZeroBalanceError: Bool = false

    /// Chronological list of completed sessions, persisted to UserDefaults.
    @Published var sessionLogs: [SessionLog] = []

    /// Activity profiles fetched from the backend.
    @Published var activityProfiles: [ActivityProfile] = []

    /// Whether a network request is in flight (for UI loading indicators).
    @Published var isLoading: Bool = false

    /// Connection status exposed from the WebSocket client.
    @Published var isConnected: Bool = false

    // MARK: - Active Session Tracking

    /// The activity profile selected for the current running session.
    @Published private(set) var activeProfile: ActivityProfile?

    /// The name of the active activity (for display in the clock ring).
    var activeActivityName: String? { activeProfile?.name }

    /// The server-assigned session ID for the active timer.
    private var activeSessionID: String?

    /// The timestamp when the current session started (from the server).
    private var sessionStartTime: Date?

    // MARK: - Dependencies

    /// WebSocket client for real-time server event streaming.
    private let wsClient: WebSocketClient

    /// Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Local UI tick timer (fires every 1s to update currentSessionTime visually).
    private var timerCancellable: AnyCancellable?

    // MARK: - Init

    init(wsClient: WebSocketClient = WebSocketClient()) {
        self.wsClient = wsClient

        // Restore persisted balance (fallback if server is offline)
        timeBalance = UserDefaults.standard.integer(forKey: Keys.timeBalance)

        // Restore session log history
        if let data = UserDefaults.standard.data(forKey: Keys.sessionLogs),
           let decoded = try? JSONDecoder().decode([SessionLog].self, from: data) {
            sessionLogs = decoded
        }

        // Request notification permission
        requestNotificationPermission()

        // Subscribe to WebSocket events
        subscribeToWSEvents()

        // Monitor connection status
        wsClient.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)

        // Connect to the server and fetch initial data
        wsClient.connect()
        fetchActivities()
    }

    // MARK: - Formatted Helpers

    /// Returns `timeBalance` formatted as **HH:mm:ss**.
    var formattedBalance: String { formatSeconds(timeBalance) }

    /// Returns `currentSessionTime` formatted as **HH:mm:ss**.
    var formattedSessionTime: String { formatSeconds(currentSessionTime) }

    // MARK: - Profile Helpers

    /// All profiles in the Top-Up category.
    var topUpProfiles: [ActivityProfile] {
        activityProfiles.filter { $0.category == .toppingUp }
    }

    /// All profiles in the Consume category.
    var consumeProfiles: [ActivityProfile] {
        activityProfiles.filter { $0.category == .consuming }
    }

    /// Adds a new activity profile locally (for offline use).
    func addProfile(_ profile: ActivityProfile) {
        activityProfiles.append(profile)
    }

    /// Removes an activity profile by ID.
    func deleteProfile(id: String) {
        activityProfiles.removeAll { $0.id == id }
    }

    // MARK: - REST API Actions

    /// Sends a POST to the backend to start a Top-Up session.
    /// **Does NOT update local state** — waits for WS broadcast.
    func startTopUp(with profile: ActivityProfile) {
        if currentState == .toppingUp {
            stopTimer()
            return
        }
        triggerHaptic(.medium)
        postStartTimer(activityID: profile.id)
    }

    /// Sends a POST to the backend to start a Consume session.
    /// **Does NOT update local state** — waits for WS broadcast.
    func startConsume(with profile: ActivityProfile) {
        guard timeBalance > 0 else {
            showZeroBalanceError = true
            triggerHaptic(.rigid)
            return
        }
        if currentState == .consuming {
            stopTimer()
            return
        }
        triggerHaptic(.medium)
        postStartTimer(activityID: profile.id)
    }

    /// Sends a POST to the backend to stop the active session.
    /// **Does NOT update local state** — waits for WS broadcast.
    func stopTimer() {
        guard currentState != .idle else { return }
        triggerHaptic(.light)
        postStopTimer()
    }

    // MARK: - HTTP Requests

    /// POST /api/timer/start?activityID=\(id)
    private func postStartTimer(activityID: String) {
        guard let url = URL(string: "\(APIConfig.timerStartURL)?activityID=\(activityID)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        isLoading = true
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
            }
            if let error = error {
                print("[API] Start error: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 {
                print("[API] Start request accepted (204)")
            }
        }.resume()
    }

    /// POST /api/timer/stop
    private func postStopTimer() {
        guard let url = URL(string: APIConfig.timerStopURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        isLoading = true
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
            }
            if let error = error {
                print("[API] Stop error: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 {
                print("[API] Stop request accepted (204)")
            }
        }.resume()
    }

    /// GET /api/activities — fetches activity profiles from the backend on launch.
    func fetchActivities() {
        guard let url = URL(string: APIConfig.activitiesURL) else { return }

        isLoading = true
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
            }
            if let error = error {
                print("[API] Fetch activities error: \(error.localizedDescription)")
                // Fall back to local defaults
                DispatchQueue.main.async {
                    if self?.activityProfiles.isEmpty == true {
                        self?.activityProfiles = ActivityProfile.allDefaults
                    }
                }
                return
            }

            guard let data = data else { return }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let profiles = try decoder.decode([ActivityProfile].self, from: data)
                DispatchQueue.main.async {
                    self?.activityProfiles = profiles
                    print("[API] Fetched \(profiles.count) activities from server")
                }
            } catch {
                print("[API] Decode activities error: \(error)")
                DispatchQueue.main.async {
                    if self?.activityProfiles.isEmpty == true {
                        self?.activityProfiles = ActivityProfile.allDefaults
                    }
                }
            }
        }.resume()
    }

    // MARK: - WebSocket Event Handling

    /// Subscribes to the WebSocket client's event stream and routes events.
    private func subscribeToWSEvents() {
        wsClient.eventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleWSEvent(event)
            }
            .store(in: &cancellables)
    }

    /// Routes an incoming WebSocket event to the appropriate handler.
    private func handleWSEvent(_ event: WSEvent) {
        switch event.type {
        case WSEventType.timerStarted:
            handleTimerStarted(event.payload)

        case WSEventType.timerStopped:
            handleTimerStopped(event.payload)

        case WSEventType.balanceUpdated:
            handleBalanceUpdated(event.payload)

        default:
            print("[WS] Unknown event type: \(event.type)")
        }
    }

    /// Handles TIMER_STARTED: sets the local state to match the server.
    private func handleTimerStarted(_ payload: [String: AnyCodable]) {
        guard let data = TimerStartedPayload(from: payload) else {
            print("[WS] Failed to parse TIMER_STARTED payload")
            return
        }

        activeSessionID = data.sessionID
        sessionStartTime = data.startTime

        // Find the matching profile
        activeProfile = activityProfiles.first { $0.id == data.activityID }

        // Set local state based on category from server
        switch data.activityCategory {
        case "toppingUp":
            currentState = .toppingUp
            currentSessionTime = 0
        case "consuming":
            currentState = .consuming
            currentSessionTime = timeBalance
        default:
            currentState = .toppingUp
            currentSessionTime = 0
        }

        // Start local UI tick timer
        startLocalTimer()

        print("[WS] Timer started: \(data.activityName) (\(data.activityCategory))")
    }

    /// Handles TIMER_STOPPED: resets to idle and logs the session locally.
    private func handleTimerStopped(_ payload: [String: AnyCodable]) {
        guard let data = TimerStoppedPayload(from: payload) else {
            print("[WS] Failed to parse TIMER_STOPPED payload")
            return
        }

        // Stop the local tick timer
        timerCancellable?.cancel()
        timerCancellable = nil

        // Log the completed session locally
        if data.duration > 0 {
            commitSession(
                type: currentState,
                duration: data.duration,
                activityName: activeProfile?.name ?? "Unknown"
            )
        }

        cancelScheduledNotification()
        activeProfile = nil
        activeSessionID = nil
        sessionStartTime = nil
        currentState = .idle
        currentSessionTime = 0

        print("[WS] Timer stopped. Duration: \(data.duration)s, Credits: \(data.creditsEarned)")
    }

    /// Handles BALANCE_UPDATED: syncs timeBalance to the server's absolute value.
    private func handleBalanceUpdated(_ payload: [String: AnyCodable]) {
        guard let data = BalanceUpdatedPayload(from: payload) else {
            print("[WS] Failed to parse BALANCE_UPDATED payload")
            return
        }

        timeBalance = data.balance
        print("[WS] Balance updated to \(data.balance) CR")
    }

    // MARK: - Local UI Timer

    /// Starts a 1-second Combine timer to update the UI between WS broadcasts.
    private func startLocalTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer
            .publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.localTick() }
    }

    /// Called every second to update the displayed session time.
    private func localTick() {
        switch currentState {
        case .toppingUp:
            currentSessionTime += 1

        case .consuming:
            currentSessionTime = max(currentSessionTime - 1, 0)
            if currentSessionTime <= 0 {
                // Balance exhausted — server will send TIMER_STOPPED
                triggerHaptic(.heavy)
            }

        case .idle:
            break
        }
    }

    // MARK: - Background / Foreground Lifecycle

    /// Called when the app goes to the background.
    func handleBackgrounded() {
        // Pause the local UI timer (server continues tracking)
        timerCancellable?.cancel()
        timerCancellable = nil

        // Schedule a notification if consuming
        if currentState == .consuming && timeBalance > 0 {
            scheduleConsumeExpiryNotification(secondsRemaining: currentSessionTime)
        }

        // Disconnect WebSocket to save resources
        wsClient.disconnect()
    }

    /// Called when the app returns to the foreground.
    func handleForegrounded() {
        cancelScheduledNotification()

        // Reconnect WebSocket
        wsClient.connect()

        // Refresh activities from server
        fetchActivities()

        // If a session was active, recalculate elapsed time from sessionStartTime
        if let startTime = sessionStartTime, currentState != .idle {
            let elapsed = Int(Date().timeIntervalSince(startTime))
            switch currentState {
            case .toppingUp:
                currentSessionTime = elapsed
            case .consuming:
                currentSessionTime = max(timeBalance - elapsed, 0)
            case .idle:
                break
            }
            startLocalTimer()
        }
    }

    // MARK: - Session Logging

    /// Saves a completed session to the persisted local log.
    private func commitSession(type: AppState, duration: Int, activityName: String) {
        guard duration > 0 else { return }
        let entry = SessionLog(
            id: UUID(),
            type: type,
            duration: duration,
            date: Date(),
            activityName: activityName
        )
        sessionLogs.append(entry)
        if let encoded = try? JSONEncoder().encode(sessionLogs) {
            UserDefaults.standard.set(encoded, forKey: Keys.sessionLogs)
        }
    }

    // MARK: - Haptic Feedback

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    private func triggerHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    // MARK: - Local Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleConsumeExpiryNotification(secondsRemaining: Int) {
        guard secondsRemaining > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time's Up!"
        content.body  = "Your entertainment time has run out. Time to top up!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(secondsRemaining),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "consume_expiry",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelScheduledNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["consume_expiry"]
        )
    }

    // MARK: - Utilities

    private func formatSeconds(_ totalSeconds: Int) -> String {
        let safe = max(totalSeconds, 0)
        let h = safe / 3600
        let m = (safe % 3600) / 60
        let s = safe % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
