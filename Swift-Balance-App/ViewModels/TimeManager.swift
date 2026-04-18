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
import FirebaseAuth

/// Core ViewModel — dual-clock delta calculation engine with Offline Sync Support.
final class TimeManager: ObservableObject {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let globalBalance  = "balance_timeBalance"
        static let sessionLogs    = "balance_sessionLogs"
        static let offlineQueue   = "balance_offlineQueue"
        static let offlineActivitiesQueue = "balance_offlineActivitiesQueue"
        static let activeSessionID = "balance_activeSessionID"
        static let activeSessionStartTimestamp = "balance_activeSessionStartTimestamp"
        static let activeSessionBaseBalance = "balance_activeSessionBaseBalance"
        static let activeSessionCategory = "balance_activeSessionCategory"
        static let activeActivityID = "balance_activeActivityID"
        static let activeActivityName = "balance_activeActivityName"
        static let guestActivities = "balance_guestActivities"
    }

    /// True when there is no Firebase user (guest/offline mode).
    private var isGuestMode: Bool {
        Auth.auth().currentUser == nil
    }

    /// Default seed activities for guest users.
    private static let defaultGuestActivities: [ActivityProfile] = [
        ActivityProfile(id: "guest_1", name: "Reading", category: .toppingUp, iconName: "book.fill", creditPerHour: 60.0),
        ActivityProfile(id: "guest_2", name: "Exercise", category: .toppingUp, iconName: "figure.run", creditPerHour: 60.0),
        ActivityProfile(id: "guest_3", name: "Meditation", category: .toppingUp, iconName: "leaf.fill", creditPerHour: 60.0),
        ActivityProfile(id: "guest_4", name: "Deep Work", category: .toppingUp, iconName: "brain.head.profile", creditPerHour: 60.0),
        ActivityProfile(id: "guest_5", name: "Gaming", category: .consuming, iconName: "gamecontroller.fill", creditPerHour: 60.0),
        ActivityProfile(id: "guest_6", name: "Social Media", category: .consuming, iconName: "bubble.left.and.bubble.right.fill", creditPerHour: 60.0),
        ActivityProfile(id: "guest_7", name: "Streaming", category: .consuming, iconName: "play.tv.fill", creditPerHour: 60.0),
    ]

    // MARK: - Published State (Dual Clock + Offline)

    @Published var currentState: AppState = .idle

    @Published var globalBalance: Int {
        didSet { UserDefaults.standard.set(globalBalance, forKey: Keys.globalBalance) }
    }

    @Published var currentSessionTime: Int = 0

    @Published var showZeroBalanceError: Bool = false

    @Published var showTopUpWarning: Bool = false

    @Published var sessionLogs: [SessionLog] = []

    @Published var activityProfiles: [ActivityProfile] = [] {
        didSet {
            // Persist locally for guest mode survival across app restarts
            if isGuestMode {
                if let encoded = try? JSONEncoder().encode(activityProfiles) {
                    UserDefaults.standard.set(encoded, forKey: Keys.guestActivities)
                }
            }
        }
    }

    @Published var isLoading: Bool = false

    @Published var isConnected: Bool = false

    @Published var offlineQueue: [OfflineSession] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(offlineQueue) {
                UserDefaults.standard.set(encoded, forKey: Keys.offlineQueue)
            }
        }
    }

    @Published var offlineActivitiesQueue: [ActivityProfile] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(offlineActivitiesQueue) {
                UserDefaults.standard.set(encoded, forKey: Keys.offlineActivitiesQueue)
            }
        }
    }

    // MARK: - Active Session Tracking

    @Published private(set) var activeProfile: ActivityProfile?

    var activeActivityName: String? { activeProfile?.name ?? activeActivityNameFallback }

    private var activeSessionID: String?
    private var activeActivityID: String?
    private var activeActivityNameFallback: String?

    private struct ActiveSessionSnapshot {
        let sessionID: String?
        let activityID: String?
        let activityName: String?
        let category: AppState
        let startTime: Date
        let baseBalance: Int
    }

    private enum ActiveSessionFetchResult {
        case active(ActiveSessionSnapshot)
        case idle
        case unavailable
    }

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

    /// True when REST APIs are reachable and user session exists.
    var isBackendAvailable: Bool {
        networkMonitor.isConnected && Auth.auth().currentUser != nil
    }

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

        if let data = UserDefaults.standard.data(forKey: Keys.offlineActivitiesQueue),
           let decoded = try? JSONDecoder().decode([ActivityProfile].self, from: data) {
            offlineActivitiesQueue = decoded
        }

        restorePersistedActiveSessionSnapshot()

        requestNotificationPermission()
        subscribeToWSEvents()

        wsClient.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)

        // Handle sync and state recovery when WS server becomes reachable
        wsClient.$isConnectedToServer
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] serverUp in
                if serverUp {
                    self?.syncOfflineData()
                    Task { [weak self] in
                        await self?.refreshActiveSessionFromBackend()
                    }
                }
            }
            .store(in: &cancellables)

        networkMonitor.$isConnected
            .dropFirst()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncOfflineData()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .userDidSignOut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearLocalData()
            }
            .store(in: &cancellables)
    }

    // MARK: - Profile Helpers

    var topUpProfiles: [ActivityProfile] { activityProfiles.filter { $0.category == .toppingUp } }
    var consumeProfiles: [ActivityProfile] { activityProfiles.filter { $0.category == .consuming } }

    func deleteProfile(id: String) { activityProfiles.removeAll { $0.id == id } }

    func addActivity(name: String, category: String, iconName: String) {
        let appCategory: AppState = category.lowercased() == "consuming" ? .consuming : .toppingUp
        let profile = ActivityProfile(
            id: UUID().uuidString,
            name: name,
            category: appCategory,
            iconName: iconName,
            creditPerHour: 60.0 // Default for custom activities
        )
        
        activityProfiles.append(profile)
        
        // Guest mode: skip networking, data is already persisted via didSet
        guard !isGuestMode else { return }
        
        if isBackendAvailable {
            postActivity(profile)
        } else {
            offlineActivitiesQueue.append(profile)
        }
    }

    // MARK: - Session Actions

    func startTopUp(with profile: ActivityProfile) {
        if currentState == .toppingUp {
            stopTimer()
            return
        }
        triggerHaptic(.medium)
        
        if isBackendAvailable {
            Task { [weak self] in
                await self?.postStartTimer(
                    activityID: profile.id,
                    fallbackProfile: profile,
                    fallbackCategory: .toppingUp
                )
            }
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
        
        if isBackendAvailable {
            Task { [weak self] in
                await self?.postStartTimer(
                    activityID: profile.id,
                    fallbackProfile: profile,
                    fallbackCategory: .consuming
                )
            }
        } else {
            startLocalOfflineSession(profile: profile, category: .consuming)
        }
    }

    func stopTimer() {
        guard currentState != .idle else { return }
        triggerHaptic(.light)
        
        if isBackendAvailable {
            Task { [weak self] in
                await self?.postStopTimer()
            }
        } else {
            stopLocalOfflineSession()
        }
    }

    // MARK: - Offline Mechanics

    private func startLocalOfflineSession(profile: ActivityProfile, category: AppState) {
        let snapshot = ActiveSessionSnapshot(
            sessionID: "offline_\(UUID().uuidString)",
            activityID: profile.id,
            activityName: profile.name,
            category: category,
            startTime: Date(),
            baseBalance: globalBalance
        )
        applyActiveSessionSnapshot(snapshot)
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
                startTime: sessionStartTime ?? Date(),
                timestamp: Date()
            )
            offlineQueue.append(offlineSession)
            
            commitSession(
                type: currentState,
                duration: duration,
                activityName: profile.name
            )
        }

        resetActiveSessionRuntime(clearPersistedState: true)
    }

    // MARK: - HTTP Requests

    /// POST start with REST fallback → offline if server unreachable.
    private func postStartTimer(activityID: String, fallbackProfile: ActivityProfile, fallbackCategory: AppState) async {
        guard let url = URL(string: "\(APIConfig.timerStartURL)?activityID=\(activityID)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        
        do {
            let token = try await AuthManager.getIDToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch {
            print("[API] Start token fetch failed: \(error.localizedDescription) — falling back to offline")
            startLocalOfflineSession(profile: fallbackProfile, category: fallbackCategory)
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 204 {
                print("[API] Start rejected (\(http.statusCode)) — falling back to offline")
                startLocalOfflineSession(profile: fallbackProfile, category: fallbackCategory)
            } else {
                let optimisticSnapshot = ActiveSessionSnapshot(
                    sessionID: activeSessionID,
                    activityID: fallbackProfile.id,
                    activityName: fallbackProfile.name,
                    category: fallbackCategory,
                    startTime: Date(),
                    baseBalance: globalBalance
                )

                await MainActor.run {
                    self.applyActiveSessionSnapshot(optimisticSnapshot)
                }

                await refreshActiveSessionFromBackend()
            }
        } catch {
            print("[API] Start failed — falling back to offline")
            startLocalOfflineSession(profile: fallbackProfile, category: fallbackCategory)
        }
    }

    private func postStopTimer() async {
        guard let url = URL(string: APIConfig.timerStopURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let token = try await AuthManager.getIDToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch {
            print("[API] Stop token fetch failed: \(error.localizedDescription) — stopping offline")
            stopLocalOfflineSession()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 204 {
                print("[API] Stop rejected (\(http.statusCode)) — stopping offline")
                stopLocalOfflineSession()
            } else {
                await MainActor.run {
                    self.resetActiveSessionRuntime(clearPersistedState: true)
                }
                await refreshActiveSessionFromBackend()
            }
        } catch {
            print("[API] Stop failed — stopping offline")
            stopLocalOfflineSession()
        }
    }

    private func postActivity(_ profile: ActivityProfile) {
        Task {
            _ = await postActivityToBackend(profile)
        }
    }

    @discardableResult
    private func postActivityToBackend(_ profile: ActivityProfile) async -> Bool {
        guard let url = URL(string: APIConfig.activitiesURL) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let token = try await AuthManager.getIDToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch {
            print("[API] Activity token fetch failed: \(error.localizedDescription)")
            return false
        }

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            request.httpBody = try encoder.encode(profile)
        } catch {
            print("[API] Activity payload encoding failed: \(error.localizedDescription)")
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("[Network] Activity upload failed: invalid HTTP response.")
                return false
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let serverMessage = String(data: data, encoding: .utf8) ?? "No response body"
                print("[Network] Activity upload failed with status \(httpResponse.statusCode): \(serverMessage)")
                return false
            }
            return true
        } catch {
            print("[API] Activity upload failed: \(error.localizedDescription)")
            return false
        }
    }

    private func syncOfflineData() {
        // Guest mode: no backend to sync with
        guard !isGuestMode else { return }

        Task {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let token: String
            do {
                token = try await AuthManager.getIDToken()
            } catch {
                print("[Sync] Token fetch failed: \(error.localizedDescription). Aborting sync.")
                return
            }
            
            // Stage 1: Sync Activities
            if !offlineActivitiesQueue.isEmpty {
                guard let url = URL(string: APIConfig.activitiesSyncURL) else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                do {
                    request.httpBody = try encoder.encode(offlineActivitiesQueue)
                    let (_, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        print("[Sync] Stage 1 failed. Aborting sync.")
                        return
                    }
                    await MainActor.run { self.offlineActivitiesQueue.removeAll() }
                } catch {
                    print("[Sync] Stage 1 error: \(error). Aborting sync.")
                    return
                }
            }
            
            // Stage 2: Sync Sessions
            if !offlineQueue.isEmpty {
                guard let url = URL(string: APIConfig.syncURL) else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                do {
                    request.httpBody = try encoder.encode(offlineQueue)
                    let (_, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        print("[Sync] Stage 2 failed.")
                        return
                    }
                    await MainActor.run { self.offlineQueue.removeAll() }
                } catch {
                    print("[Sync] Stage 2 error: \(error).")
                    return
                }
            }
            
            // Stage 3: Fetch latest external state
            await MainActor.run { self.fetchActivities() }
        }
    }

    func fetchActivities() {
        // Guest mode: load from local UserDefaults or provide defaults
        if isGuestMode {
            if let data = UserDefaults.standard.data(forKey: Keys.guestActivities),
               let decoded = try? JSONDecoder().decode([ActivityProfile].self, from: data),
               !decoded.isEmpty {
                activityProfiles = decoded
            } else if activityProfiles.isEmpty {
                activityProfiles = Self.defaultGuestActivities
            }
            resolveActiveProfileReference()
            return
        }

        Task {
            guard let url = URL(string: APIConfig.activitiesURL) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            do {
                let token = try await AuthManager.getIDToken()
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } catch {
                return
            }

            isLoading = true
            defer { isLoading = false }

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let profiles = try decoder.decode([ActivityProfile].self, from: data)

                activityProfiles = profiles
                resolveActiveProfileReference()
            } catch {
                print("[API] Fetch activities failed: \(error.localizedDescription)")
            }
        }
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

        let category: AppState = data.activityCategory.lowercased().contains("consum") ? .consuming : .toppingUp
        let snapshot = ActiveSessionSnapshot(
            sessionID: data.sessionID,
            activityID: data.activityID,
            activityName: data.activityName,
            category: category,
            startTime: data.startTime,
            baseBalance: data.baseBalance
        )

        applyActiveSessionSnapshot(snapshot)
    }

    private func handleTimerStopped(_ payload: [String: AnyCodable]) {
        guard let data = TimerStoppedPayload(from: payload) else { return }

        if data.duration > 0 {
            commitSession(
                type: currentState,
                duration: data.duration,
                activityName: activeProfile?.name ?? "Unknown"
            )
        }

        resetActiveSessionRuntime(clearPersistedState: true)
    }

    private func handleBalanceUpdated(_ payload: [String: AnyCodable]) {
        guard offlineQueue.isEmpty else { return }
        guard let data = BalanceUpdatedPayload(from: payload) else { return }
        globalBalance = data.balance
    }

    // MARK: - Active Session Persistence & Catch-Up

    private func applyActiveSessionSnapshot(_ snapshot: ActiveSessionSnapshot) {
        activeSessionID = snapshot.sessionID
        activeActivityID = snapshot.activityID
        activeActivityNameFallback = snapshot.activityName
        sessionStartTime = snapshot.startTime
        baseBalance = snapshot.baseBalance
        activeCategory = snapshot.category
        currentState = snapshot.category

        resolveActiveProfileReference()
        recalculateCurrentSessionMetrics()
        startDeltaTimerIfNeeded()
        persistActiveSessionSnapshot()
    }

    private func resetActiveSessionRuntime(clearPersistedState: Bool) {
        timerCancellable?.cancel()
        timerCancellable = nil
        cancelScheduledNotification()

        activeProfile = nil
        activeActivityID = nil
        activeActivityNameFallback = nil
        activeSessionID = nil
        sessionStartTime = nil
        baseBalance = 0
        activeCategory = .idle
        currentState = .idle
        currentSessionTime = 0

        if clearPersistedState {
            clearPersistedActiveSessionSnapshot()
        }
    }

    private func recalculateCurrentSessionMetrics() {
        guard let start = sessionStartTime, currentState != .idle else { return }

        let elapsed = max(0, Int(Date().timeIntervalSince(start)))
        currentSessionTime = elapsed

        switch activeCategory {
        case .toppingUp:
            globalBalance = baseBalance + elapsed
        case .consuming:
            globalBalance = max(baseBalance - elapsed, 0)
        case .idle:
            break
        }
    }

    private func startDeltaTimerIfNeeded() {
        guard currentState != .idle, sessionStartTime != nil else {
            timerCancellable?.cancel()
            timerCancellable = nil
            return
        }
        startDeltaTimer()
    }

    private func persistActiveSessionSnapshot() {
        guard currentState != .idle, let startTime = sessionStartTime else {
            clearPersistedActiveSessionSnapshot()
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(activeSessionID, forKey: Keys.activeSessionID)
        defaults.set(activeProfile?.id ?? activeActivityID, forKey: Keys.activeActivityID)
        defaults.set(activeProfile?.name ?? activeActivityNameFallback, forKey: Keys.activeActivityName)
        defaults.set(startTime.timeIntervalSince1970, forKey: Keys.activeSessionStartTimestamp)
        defaults.set(baseBalance, forKey: Keys.activeSessionBaseBalance)
        defaults.set(activeCategory.rawValue, forKey: Keys.activeSessionCategory)
    }

    private func restorePersistedActiveSessionSnapshot() {
        let defaults = UserDefaults.standard

        guard let categoryRaw = defaults.string(forKey: Keys.activeSessionCategory),
              let category = AppState(rawValue: categoryRaw),
              let timestamp = defaults.object(forKey: Keys.activeSessionStartTimestamp) as? Double else {
            return
        }

        let snapshot = ActiveSessionSnapshot(
            sessionID: defaults.string(forKey: Keys.activeSessionID),
            activityID: defaults.string(forKey: Keys.activeActivityID),
            activityName: defaults.string(forKey: Keys.activeActivityName),
            category: category,
            startTime: Date(timeIntervalSince1970: timestamp),
            baseBalance: defaults.object(forKey: Keys.activeSessionBaseBalance) as? Int ?? globalBalance
        )

        applyActiveSessionSnapshot(snapshot)
    }

    private func clearPersistedActiveSessionSnapshot() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.activeSessionID)
        defaults.removeObject(forKey: Keys.activeActivityID)
        defaults.removeObject(forKey: Keys.activeActivityName)
        defaults.removeObject(forKey: Keys.activeSessionStartTimestamp)
        defaults.removeObject(forKey: Keys.activeSessionBaseBalance)
        defaults.removeObject(forKey: Keys.activeSessionCategory)
    }

    private func resolveActiveProfileReference() {
        if let activeActivityID,
           let profile = activityProfiles.first(where: { $0.id == activeActivityID }) {
            activeProfile = profile
            activeActivityNameFallback = profile.name
            return
        }

        if let fallbackName = activeActivityNameFallback,
           let profile = activityProfiles.first(where: {
               $0.name.caseInsensitiveCompare(fallbackName) == .orderedSame
           }) {
            activeProfile = profile
            activeActivityID = profile.id
            activeActivityNameFallback = profile.name
        }
    }

    private func refreshActiveSessionFromBackend() async {
        let result = await fetchActiveSessionStateFromBackend()

        await MainActor.run {
            switch result {
            case .active(let snapshot):
                self.applyActiveSessionSnapshot(snapshot)
            case .idle:
                if self.activeSessionID?.hasPrefix("offline_") == true {
                    self.recalculateCurrentSessionMetrics()
                    self.startDeltaTimerIfNeeded()
                } else {
                    self.resetActiveSessionRuntime(clearPersistedState: true)
                }
            case .unavailable:
                self.recalculateCurrentSessionMetrics()
                self.startDeltaTimerIfNeeded()
            }
        }
    }

    private func fetchActiveSessionStateFromBackend() async -> ActiveSessionFetchResult {
        guard networkMonitor.isConnected else { return .unavailable }

        let token: String
        do {
            token = try await AuthManager.getIDToken()
        } catch {
            return .unavailable
        }

        for endpoint in APIConfig.timerStateURLCandidates {
            guard let url = URL(string: endpoint) else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 8
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else { continue }

                if http.statusCode == 404 || http.statusCode == 405 {
                    continue
                }

                if http.statusCode == 204 {
                    return .idle
                }

                guard (200...299).contains(http.statusCode) else {
                    return .unavailable
                }

                let parsedResult = parseActiveSessionFetchResult(from: data)
                if case .unavailable = parsedResult {
                    continue
                }

                return parsedResult
            } catch {
                print("[API] Active session fetch failed for \(endpoint): \(error.localizedDescription)")
            }
        }

        return .unavailable
    }

    private func parseActiveSessionFetchResult(from data: Data) -> ActiveSessionFetchResult {
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let envelope = rawObject as? [String: Any] else {
            return .unavailable
        }

        let root = (envelope["session"] as? [String: Any])
            ?? (envelope["data"] as? [String: Any])
            ?? envelope

        let activeFlag = boolValue(from: root, keys: ["active", "isActive", "running"])
            ?? boolValue(from: envelope, keys: ["active", "isActive", "running"])

        if activeFlag == false {
            return .idle
        }

        guard let startTime = dateValue(from: root, keys: ["startTime", "startedAt", "started_at", "start"])
                ?? dateValue(from: envelope, keys: ["startTime", "startedAt", "started_at", "start"]) else {
            return activeFlag == true ? .unavailable : .idle
        }

        let categoryRaw = stringValue(from: root, keys: ["activityCategory", "category", "type"])
            ?? stringValue(from: envelope, keys: ["activityCategory", "category", "type"])
            ?? activeCategory.rawValue

        let category: AppState = categoryRaw.lowercased().contains("consum") ? .consuming : .toppingUp

        let baseBalance = intValue(from: root, keys: ["baseBalance", "startingBalance", "balanceAtStart", "base_balance"])
            ?? intValue(from: envelope, keys: ["baseBalance", "startingBalance", "balanceAtStart", "base_balance"])
            ?? globalBalance

        let snapshot = ActiveSessionSnapshot(
            sessionID: stringValue(from: root, keys: ["sessionID", "sessionId", "id"])
                ?? stringValue(from: envelope, keys: ["sessionID", "sessionId", "id"]),
            activityID: stringValue(from: root, keys: ["activityID", "activityId"])
                ?? stringValue(from: envelope, keys: ["activityID", "activityId"]),
            activityName: stringValue(from: root, keys: ["activityName", "name"])
                ?? stringValue(from: envelope, keys: ["activityName", "name"]),
            category: category,
            startTime: startTime,
            baseBalance: baseBalance
        )

        return .active(snapshot)
    }

    private func stringValue(from dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func boolValue(from dict: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dict[key] as? Bool {
                return value
            }
            if let value = dict[key] as? NSNumber {
                return value.boolValue
            }
            if let value = dict[key] as? String {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalized == "true" || normalized == "1" {
                    return true
                }
                if normalized == "false" || normalized == "0" {
                    return false
                }
            }
        }
        return nil
    }

    private func intValue(from dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dict[key] as? Int {
                return value
            }
            if let value = dict[key] as? Double {
                return Int(value)
            }
            if let value = dict[key] as? NSNumber {
                return value.intValue
            }
            if let value = dict[key] as? String, let intValue = Int(value) {
                return intValue
            }
        }
        return nil
    }

    private func dateValue(from dict: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            guard let raw = dict[key] else { continue }

            if let seconds = raw as? TimeInterval {
                return seconds > 1_000_000_000_000
                    ? Date(timeIntervalSince1970: seconds / 1000.0)
                    : Date(timeIntervalSince1970: seconds)
            }

            if let number = raw as? NSNumber {
                let seconds = number.doubleValue
                return seconds > 1_000_000_000_000
                    ? Date(timeIntervalSince1970: seconds / 1000.0)
                    : Date(timeIntervalSince1970: seconds)
            }

            if let text = raw as? String {
                let formatterWithFractional = ISO8601DateFormatter()
                formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = formatterWithFractional.date(from: text) {
                    return parsed
                }

                let formatterBasic = ISO8601DateFormatter()
                formatterBasic.formatOptions = [.withInternetDateTime]
                if let parsed = formatterBasic.date(from: text) {
                    return parsed
                }
            }
        }

        return nil
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
        recalculateCurrentSessionMetrics()

        guard currentState == .consuming, globalBalance <= 0 else { return }

        // Circuit breaker: CR depleted — force stop the consuming session
        triggerHaptic(.heavy)
        stopLocalOfflineSession()
        showTopUpWarning = true
    }

    // MARK: - Background / Foreground Lifecycle

    func clearLocalData() {
        timerCancellable?.cancel()
        timerCancellable = nil

        cancelScheduledNotification()

        activeProfile = nil
        activeActivityID = nil
        activeActivityNameFallback = nil
        activeSessionID = nil
        sessionStartTime = nil
        baseBalance = 0
        activeCategory = .idle

        currentState = .idle
        currentSessionTime = 0
        globalBalance = 0
        showZeroBalanceError = false
        sessionLogs = []
        activityProfiles = []
        offlineQueue = []
        offlineActivitiesQueue = []
        isLoading = false

        UserDefaults.standard.removeObject(forKey: Keys.globalBalance)
        UserDefaults.standard.removeObject(forKey: Keys.sessionLogs)
        UserDefaults.standard.removeObject(forKey: Keys.offlineQueue)
        UserDefaults.standard.removeObject(forKey: Keys.offlineActivitiesQueue)
        clearPersistedActiveSessionSnapshot()
    }

    func handleBackgrounded() {
        // Guard: already suspended — inactive→background fires twice
        guard wsClient.isConnected || timerCancellable != nil || currentState != .idle else { return }

        print("[Lifecycle] App backgrounded — suspending socket & timer")

        persistActiveSessionSnapshot()

        timerCancellable?.cancel()
        timerCancellable = nil

        if currentState == .consuming && globalBalance > 0 {
            scheduleConsumeExpiryNotification(secondsRemaining: globalBalance)
        }

        wsClient.disconnect(reason: "app backgrounded")
    }

    func handleForegrounded() {
        // Guest mode: restore local state only, no networking
        if isGuestMode {
            print("[Lifecycle] App foregrounded (guest mode) — restoring local state")
            cancelScheduledNotification()
            fetchActivities()
            restorePersistedActiveSessionSnapshot()
            recalculateCurrentSessionMetrics()
            startDeltaTimerIfNeeded()
            return
        }

        guard Auth.auth().currentUser != nil else {
            wsClient.disconnect(reason: "user session unavailable")
            return
        }

        print("[Lifecycle] App foregrounded — reconnecting socket")
        cancelScheduledNotification()
        wsClient.connect(forceReconnect: true)
        fetchActivities()

        restorePersistedActiveSessionSnapshot()
        recalculateCurrentSessionMetrics()
        startDeltaTimerIfNeeded()

        Task { [weak self] in
            await self?.refreshActiveSessionFromBackend()
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
