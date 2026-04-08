//
//  AppState.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-08.
//

import Foundation

/// Represents the three possible states of the Balance app timer.
enum AppState: String, CaseIterable {
    /// No timer is running.
    case idle
    /// The user is accumulating constructive time (credit).
    case toppingUp
    /// The user is spending entertainment time (debit).
    case consuming
}
