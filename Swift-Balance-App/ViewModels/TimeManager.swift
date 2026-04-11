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

/// Core ViewModel — dual-clock delta calculation engine.
///
/// **Architecture:**
/// - Buttons → REST API → Server processes → WS broadcast → iOS state
/// - TIMER_STARTED carries `baseBalance` + `startTime`
/// - Local Combine timer ticks every 1s, computing:
///   - `currentSessionTime = elapsed since startTime`
///   - `globalBalance = baseBalance ± elapsed` (+ for topUp, - for consume)
/// - TIMER_STOPPED / BALANCE_UPDATED snap `globalBalance` to server truth
final class TimeManager: ObservableObject {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let globalBalance  = "balance_timeBalance"
        static let sessionLogs    = "balance_sessionLogs"
    }

    // MARK: - Published State (Dual Clock)

    /// App state machine.
    @Published var currentState: AppState = .idle

    /// Global CR pool — ticks live during sessions via delta calc.
    @Published var globalBalance: Int {
        didSet { UserDefaults.standard.set(globalBalance, forKey: Keys.globalBalance) }
    }

    /// Active session elapsed seconds — ticks every 1s.
    @Published var currentSessionTime: Int = 0

    /// Zero-balance guard alert trigger.
    @Published var showZeroBalanceError: Bool = false

    /// Session history log.
    @Published var sessionLogs: [SessionLog] = []

    /// Server-fetched activity profiles.
    @Published var activityProfiles: [ActivityProfile] = []

    /// Network loading indicator.
    @Published var isLoading: Bool = false

    /// WebSocket connection status.
    @Published var isConnected: Bool = false

    // MARK: - Active Session Tracking

    /// Currently running activity profile.
    @Published private(set) var activeProfile: ActivityProfile?

    /// Active activity name for clock ring display.
    var activeActivityName: String? { activeProfile?.name }

    /// Server-assigned session ID.
    private var activeSessionID: String?

    // MARK: - Delta Calculation Internals

    /// Server timestamp when session started — anchor for elapsed calc.
    private var sessionStartTime: Date?

    /// CR pool snapshot at session start — baseline for delta addition.
    private var baseBalance: Int = 0

    /// Category of active session — determines +/- direction.
    private var activeCategory: AppState = .idle

    // MARK: - Dependencies

    private let wsClient: WebSocketClient
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?

    // MARK: - Formatted Helpers

    /// `globalBalance` as HH:mm:ss.
    var formattedBalance: String { formatSeconds(globalBalance) }

    /// `currentSessionTime` as HH:mm:ss.
    var formattedSessionTime: String { formatSeconds(currentSessionTime) }

    // MARK: - Init

    init(wsClient: WebSocketClient = WebSocketClient()) {
        self.wsClient = wsClient

        // Restore persisted balance (fallback if server offline)
        globalBalance = UserDefaults.standard.integer(forKey: Keys.globalBalance)

        // Restore session logs
        if let data = UserDefaults.standard.data(forKey: Keys.sessionLogs),
           let decoded = try? JSONDecoder().decode([SessionLog].self, from: data) {
            sessionLogs = decoded
        }

        requestNotificationPermission()
        subscribeToWSEvents()

        wsClient.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)

        wsClient.connect()
        fetchActivities()
    }

    // MARK: - Profile Helpers

    var topUpProfiles: [ActivityProfile] {
        activityProfiles.filter { $0.category == .toppingUp }
    }

    var consumeProfiles: [ActivityProfile] {
        activityProfiles.filter { $0.category == .consuming }
    }

    func addProfile(_ profile: ActivityProfile) {
        activityProfiles.append(profile)
    }

    func deleteProfile(id: String) {
        activityProfiles.removeAll { $0.id == id }
    }

    // MARK: - REST API Actions

    /// POST start — no local state change, wait for WS.
    func startTopUp(with profile: ActivityProfile) {
        if currentState == .toppingUp {
            stopTimer()
            return
        }
        triggerHaptic(.medium)
        postStartTimer(activityID: profile.id)
    }

    /// POST start consume — guard zero balance.
    func startConsume(with profile: ActivityProfile) {
        guard globalBalance > 0 else {
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

    /// POST stop — no local state change, wait for WS.
    func stopTimer() {
        guard currentState != .idle else { return }
        triggerHaptic(.light)
        postStopTimer()
    }

    // MARK: - HTTP Requests

    private func postStartTimer(activityID: String) {
        guard let url = URL(string: "\(APIConfig.timerStartURL)?activityID=\(activityID)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        isLoading = true
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async { self?.isLoading = false }
            if let error = error {
                print("[API] Start error: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 204 {
                print("[API] Start accepted (204)")
            }
        }.resume()
    }

    private func postStopTimer() {
        guard let url = URL(string: APIConfig.timerStopURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        isLoading = true
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async { self?.isLoading = false }
            if let error = error {
                print("[API] Stop error: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 204 {
                print("[API] Stop accepted (204)")
            }
        }.resume()
    }

    func fetchActivities() {
        guard let url = URL(string: APIConfig.activitiesURL) else { return }

        isLoading = true
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async { self?.isLoading = false }
            if let error = error {
                print("[API] Fetch activities error: \(error.localizedDescription)")
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
                    print("[API] Fetched \(profiles.count) activities")
                }
            } catch {
                print("[API] Decode error: \(error)")
                DispatchQueue.main.async {
                    if self?.activityProfiles.isEmpty == true {
                        self?.activityProfiles = ActivityProfile.allDefaults
                    }
                }
            }
        }.resume()
    }

    // MARK: - WebSocket Event Handling

    private func subscribeToWSEvents() {
        wsClient.eventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handleWSEvent(event) }
            .store(in: &cancellables)
    }

    private func handleWSEvent(_ event: WSEvent) {
        switch event.type {
        case WSEventType.timerStarted:
            handleTimerStarted(event.payload)
        case WSEventType.timerStopped:
            handleTimerStopped(event.payload)
        case WSEventType.balanceUpdated:
            handleBalanceUpdated(event.payload)
        default:
            print("[WS] Unknown event: \(event.type)")
        }
    }

    // MARK: - TIMER_STARTED → Delta Engine Start

    private func handleTimerStarted(_ payload: [String: AnyCodable]) {
        guard let data = TimerStartedPayload(from: payload) else {
            print("[WS] Failed parse TIMER_STARTED")
            return
        }

        // Store delta calc anchors
        activeSessionID = data.sessionID
        sessionStartTime = data.startTime
        baseBalance = data.baseBalance
        activeCategory = data.activityCategory == "consuming" ? .consuming : .toppingUp

        // Match profile
        activeProfile = activityProfiles.first { $0.id == data.activityID }

        // Set state + initial values
        currentState = activeCategory
        currentSessionTime = 0
        globalBalance = data.baseBalance

        // Start delta tick timer
        startDeltaTimer()

        print("[WS] Started: \(data.activityName) (\(data.activityCategory)) base=\(data.baseBalance)")
    }

    // MARK: - TIMER_STOPPED → Snap to Server Truth

    private func handleTimerStopped(_ payload: [String: AnyCodable]) {
        guard let data = TimerStoppedPayload(from: payload) else {
            print("[WS] Failed parse TIMER_STOPPED")
            return
        }

        // Kill delta timer
        timerCancellable?.cancel()
        timerCancellable = nil

        // Log session locally
        if data.duration > 0 {
            commitSession(
                type: currentState,
                duration: data.duration,
                activityName: activeProfile?.name ?? "Unknown"
            )
        }

        // Reset everything
        cancelScheduledNotification()
        activeProfile = nil
        activeSessionID = nil
        sessionStartTime = nil
        baseBalance = 0
        activeCategory = .idle
        currentState = .idle
        currentSessionTime = 0

        print("[WS] Stopped. Duration: \(data.duration)s, Credits: \(data.creditsEarned)")
    }

    // MARK: - BALANCE_UPDATED → Absolute Snap

    private func handleBalanceUpdated(_ payload: [String: AnyCodable]) {
        guard let data = BalanceUpdatedPayload(from: payload) else {
            print("[WS] Failed parse BALANCE_UPDATED")
            return
        }

        // Server truth corrects any local drift
        globalBalance = data.balance
        print("[WS] Balance snapped to \(data.balance) CR")
    }

    // MARK: - Delta Calculation Timer

    /// Ticks every 1s. Computes elapsed from sessionStartTime.
    /// Updates both clocks: session elapsed + global CR pool.
    private func startDeltaTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer
            .publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.deltaTick() }
    }

    /// Core delta tick — single source of animated truth.
    private func deltaTick() {
        guard let start = sessionStartTime else { return }

        let elapsed = Int(Date().timeIntervalSince(start))
        currentSessionTime = elapsed

        switch activeCategory {
        case .toppingUp:
            globalBalance = baseBalance + elapsed

        case .consuming:
            globalBalance = max(baseBalance - elapsed, 0)
            if globalBalance <= 0 {
                triggerHaptic(.heavy)
                // Server will send TIMER_STOPPED when it detects expiry
            }

        case .idle:
            break
        }
    }

    // MARK: - Background / Foreground Lifecycle

    func handleBackgrounded() {
        timerCancellable?.cancel()
        timerCancellable = nil

        if currentState == .consuming && globalBalance > 0 {
            scheduleConsumeExpiryNotification(secondsRemaining: globalBalance)
        }

        wsClient.disconnect()
    }

    func handleForegrounded() {
        cancelScheduledNotification()
        wsClient.connect()
        fetchActivities()

        // Recalculate from anchor if session active
        if let start = sessionStartTime, currentState != .idle {
            let elapsed = Int(Date().timeIntervalSince(start))
            currentSessionTime = elapsed

            switch activeCategory {
            case .toppingUp:
                globalBalance = baseBalance + elapsed
            case .consuming:
                globalBalance = max(baseBalance - elapsed, 0)
            case .idle:
                break
            }

            startDeltaTimer()
        }
    }

    // MARK: - Session Logging

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

    // MARK: - Haptics

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func triggerHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    // MARK: - Notifications

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
