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
/// Responsibilities:
/// - Timer state machine (idle / toppingUp / consuming)
/// - UserDefaults persistence for balance, session history, and activity profiles
/// - Background-foreground lifecycle delta calculation
/// - Haptic feedback on state transitions
/// - Local notification scheduling for Consume expiry
final class TimeManager: ObservableObject {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let timeBalance       = "balance_timeBalance"
        static let sessionLogs       = "balance_sessionLogs"
        static let activityProfiles  = "balance_activityProfiles"
    }

    // MARK: - Published State

    /// The current operational state of the app.
    @Published var currentState: AppState = .idle

    /// Total accumulated credit in seconds — persisted across launches.
    @Published var timeBalance: Int {
        didSet { UserDefaults.standard.set(timeBalance, forKey: Keys.timeBalance) }
    }

    /// Elapsed (top-up) or remaining (consume) seconds for the running session.
    @Published var currentSessionTime: Int = 0

    /// Set to true when the user taps Consume with a zero balance; triggers an alert in the UI.
    @Published var showZeroBalanceError: Bool = false

    /// Chronological list of completed sessions, persisted to UserDefaults.
    @Published var sessionLogs: [SessionLog] = []

    /// Configurable activity profiles — persisted to UserDefaults.
    @Published var activityProfiles: [ActivityProfile] = [] {
        didSet { persistProfiles() }
    }

    // MARK: - Active Session Tracking

    /// The activity profile selected for the current running session.
    private(set) var activeProfile: ActivityProfile?

    // MARK: - Private

    /// Stores the Combine cancellable for the 1-second tick publisher.
    private var timerCancellable: AnyCancellable?

    /// Timestamp captured when the app moves to the background.
    private var backgroundedAt: Date?

    /// Tracks the state that was active when the app backgrounded.
    private var stateWhenBackgrounded: AppState = .idle

    /// Seconds elapsed during the current session at the moment the app backgrounded.
    private var sessionTimeWhenBackgrounded: Int = 0

    // MARK: - Init

    init() {
        // Restore persisted balance (0 on first launch)
        timeBalance = UserDefaults.standard.integer(forKey: Keys.timeBalance)

        // Restore session log history
        if let data = UserDefaults.standard.data(forKey: Keys.sessionLogs),
           let decoded = try? JSONDecoder().decode([SessionLog].self, from: data) {
            sessionLogs = decoded
        }

        // Restore or seed activity profiles
        if let data = UserDefaults.standard.data(forKey: Keys.activityProfiles),
           let decoded = try? JSONDecoder().decode([ActivityProfile].self, from: data) {
            activityProfiles = decoded
        } else {
            activityProfiles = ActivityProfile.allDefaults
        }

        // Request notification permission on first init
        requestNotificationPermission()
    }

    // MARK: - Formatted Helpers

    /// Returns `timeBalance` formatted as **HH:mm:ss**.
    var formattedBalance: String { formatSeconds(timeBalance) }

    /// Returns `currentSessionTime` formatted as **HH:mm:ss**.
    var formattedSessionTime: String { formatSeconds(currentSessionTime) }

    /// Returns the name of the currently active activity, or nil.
    var activeActivityName: String? { activeProfile?.name }

    // MARK: - Profile Helpers

    /// All profiles in the Top-Up category.
    var topUpProfiles: [ActivityProfile] {
        activityProfiles.filter { $0.category == .toppingUp }
    }

    /// All profiles in the Consume category.
    var consumeProfiles: [ActivityProfile] {
        activityProfiles.filter { $0.category == .consuming }
    }

    /// Adds a new activity profile.
    func addProfile(_ profile: ActivityProfile) {
        activityProfiles.append(profile)
    }

    /// Removes an activity profile by ID.
    func deleteProfile(id: UUID) {
        activityProfiles.removeAll { $0.id == id }
    }

    // MARK: - State Transitions

    /// Begins a Top-Up session with a specific activity, or stops it if already active.
    func startTopUp(with profile: ActivityProfile) {
        if currentState == .toppingUp {
            stopTimer()
            return
        }
        stopTimer()
        triggerHaptic(.medium)
        activeProfile = profile
        currentState = .toppingUp
        currentSessionTime = 0
        startCombineTimer()
    }

    /// Begins a Consume session with a specific activity, or stops it if already active.
    /// Shows an alert when the balance is zero.
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
        stopTimer()
        triggerHaptic(.medium)
        activeProfile = profile
        currentState = .consuming
        currentSessionTime = timeBalance
        startCombineTimer()
    }

    /// Stops whichever timer is running and commits the session log.
    func stopTimer() {
        guard currentState != .idle else { return }
        timerCancellable?.cancel()
        timerCancellable = nil

        // Log the completed session
        let sessionDuration: Int
        if currentState == .toppingUp {
            sessionDuration = currentSessionTime
        } else {
            // For consume, duration is how much was actually consumed
            // (original balance at start minus what's left)
            sessionDuration = max(0, (activeProfile != nil ? currentSessionTime : 0))
        }

        if sessionDuration > 0 {
            commitSession(
                type: currentState,
                duration: sessionDuration,
                activityName: activeProfile?.name ?? "Unknown"
            )
        }

        triggerHaptic(.light)
        cancelScheduledNotification()
        activeProfile = nil
        currentState = .idle
    }

    // MARK: - Background / Foreground Lifecycle

    /// Called by the App struct when the scene moves to the background.
    func handleBackgrounded() {
        backgroundedAt = Date()
        stateWhenBackgrounded = currentState
        sessionTimeWhenBackgrounded = currentSessionTime

        // Pause the Combine timer — we'll calculate offline time on resume
        timerCancellable?.cancel()
        timerCancellable = nil

        // If consuming, schedule a notification for when the balance will expire
        if currentState == .consuming && timeBalance > 0 {
            scheduleConsumeExpiryNotification(secondsRemaining: timeBalance)
        }
    }

    /// Called by the App struct when the scene returns to the foreground.
    func handleForegrounded() {
        cancelScheduledNotification()

        guard let bgDate = backgroundedAt else { return }
        backgroundedAt = nil

        let elapsed = Int(Date().timeIntervalSince(bgDate))
        guard elapsed > 0 else { return }

        switch stateWhenBackgrounded {
        case .toppingUp:
            currentSessionTime = sessionTimeWhenBackgrounded + elapsed
            timeBalance       += elapsed

        case .consuming:
            let debit = min(elapsed, timeBalance)
            currentSessionTime = max(sessionTimeWhenBackgrounded - elapsed, 0)
            timeBalance       -= debit

            if timeBalance <= 0 {
                commitSession(
                    type: .consuming,
                    duration: sessionTimeWhenBackgrounded,
                    activityName: activeProfile?.name ?? "Unknown"
                )
                triggerHaptic(.heavy)
                activeProfile = nil
                currentState = .idle
                return
            }

        case .idle:
            return
        }

        // Resume the live timer
        startCombineTimer()
    }

    // MARK: - Combine Timer

    private func startCombineTimer() {
        timerCancellable = Timer
            .publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    /// Called every second by the Combine timer.
    private func tick() {
        switch currentState {
        case .toppingUp:
            currentSessionTime += 1
            timeBalance        += 1

        case .consuming:
            guard timeBalance > 0 else {
                triggerHaptic(.heavy)
                stopTimer()
                return
            }
            currentSessionTime -= 1
            timeBalance        -= 1
            if timeBalance <= 0 {
                triggerHaptic(.heavy)
                stopTimer()
            }

        case .idle:
            break
        }
    }

    // MARK: - Session Logging

    /// Saves a completed session to the persisted log.
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

    // MARK: - Persistence Helpers

    private func persistProfiles() {
        if let encoded = try? JSONEncoder().encode(activityProfiles) {
            UserDefaults.standard.set(encoded, forKey: Keys.activityProfiles)
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

    /// Schedules a notification to fire when the Consume balance reaches zero.
    private func scheduleConsumeExpiryNotification(secondsRemaining: Int) {
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

    /// Cancels any pending consume-expiry notification.
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
