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

/// Core ViewModel — dual-clock delta calculation engine with Offline Sync Support.
final class TimeManager: ObservableObject {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let globalBalance  = "balance_timeBalance"
        static let sessionLogs    = "balance_sessionLogs"
        static let offlineQueue   = "balance_offlineQueue"
    }

    // MARK: - Published State (Dual Clock + Offline)

    @Published var currentState: AppState = .idle

    @Published var globalBalance: Int {
        didSet { UserDefaults.standard.set(globalBalance, forKey: Keys.globalBalance) }
    }

    @Published var currentSessionTime: Int = 0

    @Published var showZeroBalanceError: Bool = false

    @Published var sessionLogs: [SessionLog] = []

    @Published var activityProfiles: [ActivityProfile] = []

    @Published var isLoading: Bool = false

    @Published var isConnected: Bool = false

    @Published var offlineQueue: [OfflineSession] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(offlineQueue) {
                UserDefaults.standard.set(encoded, forKey: Keys.offlineQueue)
            }
        }
    }

    // MARK: - Active Session Tracking

    @Published private(set) var activeProfile: ActivityProfile?

    var activeActivityName: String? { activeProfile?.name }

    private var activeSessionID: String?

    // MARK: - Delta Calculation Internals

    private var sessionStartTime: Date?
    private var baseBalance: Int = 0
    private var activeCategory: AppState = .idle

    // MARK: - Dependencies

    private let wsClient: WebSocketClient
    private let networkMonitor: NetworkMonitor
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?

    // MARK: - Formatted Helpers

    var formattedBalance: String { formatSeconds(globalBalance) }
    var formattedSessionTime: String { formatSeconds(currentSessionTime) }

    // MARK: - Init

    init(wsClient: WebSocketClient = WebSocketClient(), networkMonitor: NetworkMonitor = NetworkMonitor()) {
        self.wsClient = wsClient
        self.networkMonitor = networkMonitor

        globalBalance = UserDefaults.standard.integer(forKey: Keys.globalBalance)

        if let data = UserDefaults.standard.data(forKey: Keys.sessionLogs),
           let decoded = try? JSONDecoder().decode([SessionLog].self, from: data) {
            sessionLogs = decoded
        }

        if let data = UserDefaults.standard.data(forKey: Keys.offlineQueue),
           let decoded = try? JSONDecoder().decode([OfflineSession].self, from: data) {
            offlineQueue = decoded
        }

        requestNotificationPermission()
        subscribeToWSEvents()

        wsClient.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)

        networkMonitor.$isConnected
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOnline in
                if isOnline {
                    self?.syncOfflineData()
                }
            }
            .store(in: &cancellables)

        wsClient.connect()
        fetchActivities()
    }

    // MARK: - Profile Helpers

    var topUpProfiles: [ActivityProfile] { activityProfiles.filter { $0.category == .toppingUp } }
    var consumeProfiles: [ActivityProfile] { activityProfiles.filter { $0.category == .consuming } }

    func addProfile(_ profile: ActivityProfile) { activityProfiles.append(profile) }
    func deleteProfile(id: String) { activityProfiles.removeAll { $0.id == id } }

    // MARK: - Session Actions

    func startTopUp(with profile: ActivityProfile) {
        if currentState == .toppingUp {
            stopTimer()
            return
        }
        triggerHaptic(.medium)
        
        if networkMonitor.isConnected {
            postStartTimer(activityID: profile.id)
        } else {
            startLocalOfflineSession(profile: profile, category: .toppingUp)
        }
    }

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
        
        if networkMonitor.isConnected {
            postStartTimer(activityID: profile.id)
        } else {
            startLocalOfflineSession(profile: profile, category: .consuming)
        }
    }

    func stopTimer() {
        guard currentState != .idle else { return }
        triggerHaptic(.light)
        
        if networkMonitor.isConnected {
            postStopTimer()
        } else {
            stopLocalOfflineSession()
        }
    }

    // MARK: - Offline Mechanics

    private func startLocalOfflineSession(profile: ActivityProfile, category: AppState) {
        activeProfile = profile
        activeSessionID = "offline_\(UUID().uuidString)"
        sessionStartTime = Date()
        baseBalance = globalBalance
        activeCategory = category
        currentState = category
        currentSessionTime = 0

        startDeltaTimer()
    }

    private func stopLocalOfflineSession() {
        timerCancellable?.cancel()
        timerCancellable = nil

        let duration = currentSessionTime
        let creditsEarned: Int
        
        if currentState == .toppingUp {
            let hourlyRate = activeProfile?.creditPerHour ?? 60.0
            creditsEarned = Int(Double(duration) * (hourlyRate / 3600.0))
        } else {
            creditsEarned = -duration
        }

        if duration > 0, let profile = activeProfile {
            let offlineSession = OfflineSession(
                activityID: profile.id,
                duration: duration,
                creditsEarned: creditsEarned,
                timestamp: Date()
            )
            offlineQueue.append(offlineSession)
            
            commitSession(
                type: currentState,
                duration: duration,
                activityName: profile.name
            )
        }

        cancelScheduledNotification()
        activeProfile = nil
        activeSessionID = nil
        sessionStartTime = nil
        baseBalance = 0
        activeCategory = .idle
        currentState = .idle
        currentSessionTime = 0
    }

    // MARK: - HTTP Requests

    private func postStartTimer(activityID: String) {
        guard let url = URL(string: "\(APIConfig.timerStartURL)?activityID=\(activityID)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        isLoading = true
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async { self?.isLoading = false }
        }.resume()
    }

    private func postStopTimer() {
        guard let url = URL(string: APIConfig.timerStopURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        isLoading = true
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async { self?.isLoading = false }
        }.resume()
    }

    private func syncOfflineData() {
        guard !offlineQueue.isEmpty else { return }
        guard let url = URL(string: APIConfig.syncURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(offlineQueue)
        } catch {
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            DispatchQueue.main.async {
                self?.offlineQueue.removeAll()
            }
        }.resume()
    }

    func fetchActivities() {
        guard let url = URL(string: APIConfig.activitiesURL) else { return }

        isLoading = true
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async { self?.isLoading = false }
            if error != nil {
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
                }
            } catch {
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
            break
        }
    }

    private func handleTimerStarted(_ payload: [String: AnyCodable]) {
        guard let data = TimerStartedPayload(from: payload) else { return }

        activeSessionID = data.sessionID
        sessionStartTime = data.startTime
        baseBalance = data.baseBalance
        activeCategory = data.activityCategory == "consuming" ? .consuming : .toppingUp

        activeProfile = activityProfiles.first { $0.id == data.activityID }

        currentState = activeCategory
        currentSessionTime = 0
        globalBalance = data.baseBalance

        startDeltaTimer()
    }

    private func handleTimerStopped(_ payload: [String: AnyCodable]) {
        guard let data = TimerStoppedPayload(from: payload) else { return }

        timerCancellable?.cancel()
        timerCancellable = nil

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
        baseBalance = 0
        activeCategory = .idle
        currentState = .idle
        currentSessionTime = 0
    }

    private func handleBalanceUpdated(_ payload: [String: AnyCodable]) {
        guard let data = BalanceUpdatedPayload(from: payload) else { return }
        globalBalance = data.balance
    }

    // MARK: - Delta Calculation Timer

    private func startDeltaTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer
            .publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.deltaTick() }
    }

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
                if !networkMonitor.isConnected {
                    stopLocalOfflineSession()
                }
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
