//
//  TimeManager.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-08.
//

import Foundation
import Combine

/// The core ViewModel that drives the Balance app's timer engine.
///
/// `TimeManager` owns all timer state and exposes `@Published` properties
/// that SwiftUI views observe for live updates. It uses a Combine
/// `Timer.publish` pipeline that fires every second to tick the clock.
final class TimeManager: ObservableObject {

    // MARK: - Published State

    /// The current operational state of the app.
    @Published var currentState: AppState = .idle

    /// Total accumulated credit in seconds.
    /// Initialised with a mock value of 4 500 s (≈ 1 250 CR for testing).
    @Published var timeBalance: Int = 4500

    /// Elapsed (top-up) or remaining (consume) seconds for the running session.
    @Published var currentSessionTime: Int = 0

    // MARK: - Private

    /// Stores the Combine cancellable for the timer publisher.
    private var timerCancellable: AnyCancellable?

    // MARK: - Formatted Helpers

    /// Returns `timeBalance` formatted as **H:MM:SS**.
    var formattedBalance: String {
        formatSeconds(timeBalance)
    }

    /// Returns `currentSessionTime` formatted as **HH:mm:ss**.
    var formattedSessionTime: String {
        formatSeconds(currentSessionTime)
    }

    // MARK: - State Transitions

    /// Begins a Top-Up session, or stops the current timer if already topping up.
    func startTopUp() {
        if currentState == .toppingUp {
            stopTimer()
            return
        }
        stopTimer()                       // cancel any prior session
        currentState = .toppingUp
        currentSessionTime = 0
        startCombineTimer()
    }

    /// Begins a Consume session, or stops the current timer if already consuming.
    func startConsume() {
        guard timeBalance > 0 else { return }   // nothing to spend
        if currentState == .consuming {
            stopTimer()
            return
        }
        stopTimer()
        currentState = .consuming
        currentSessionTime = timeBalance        // countdown starts at full balance
        startCombineTimer()
    }

    /// Stops whichever timer is running and resets to `.idle`.
    func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        currentState = .idle
    }

    // MARK: - Combine Timer

    /// Creates a 1-second Combine timer and wires tick handling.
    private func startCombineTimer() {
        timerCancellable = Timer
            .publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    /// Called every second by the Combine timer publisher.
    private func tick() {
        switch currentState {
        case .toppingUp:
            currentSessionTime += 1
            timeBalance += 1

        case .consuming:
            guard timeBalance > 0 else {
                stopTimer()
                return
            }
            currentSessionTime -= 1
            timeBalance -= 1
            if timeBalance <= 0 {
                stopTimer()
            }

        case .idle:
            break
        }
    }

    // MARK: - Utilities

    /// Converts total seconds into an **HH:mm:ss** string.
    private func formatSeconds(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
