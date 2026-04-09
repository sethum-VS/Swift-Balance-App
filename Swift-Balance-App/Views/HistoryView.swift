//
//  HistoryView.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-09.
//

import SwiftUI

/// Tab 2 — displays completed sessions grouped by date, most recent first.
struct HistoryView: View {
    @EnvironmentObject var timeManager: TimeManager

    /// Sessions grouped by calendar day (descending).
    private var groupedSessions: [(String, [SessionLog])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let grouped = Dictionary(grouping: timeManager.sessionLogs) { log in
            formatter.string(from: log.date)
        }

        // Sort groups by the most recent session date descending
        return grouped
            .sorted { lhs, rhs in
                guard let l = lhs.value.first?.date, let r = rhs.value.first?.date else { return false }
                return l > r
            }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if timeManager.sessionLogs.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("History")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: 0x6C63FF).opacity(0.5))

            Text("No sessions yet")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            Text("Start a Top-Up or Consume session\nto see your history here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            ForEach(groupedSessions, id: \.0) { dateString, sessions in
                Section {
                    ForEach(sessions) { session in
                        sessionRow(session)
                            .listRowBackground(Color.white.opacity(0.04))
                    }
                } header: {
                    Text(dateString)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Row

    private func sessionRow(_ session: SessionLog) -> some View {
        HStack(spacing: 12) {
            // Category indicator
            Circle()
                .fill(session.type == .toppingUp
                      ? Color(hex: 0x00E5A0)
                      : Color(hex: 0xFC466B))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.activityName)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)

                Text(session.typeLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(session.type == .toppingUp
                                     ? Color(hex: 0x00E5A0).opacity(0.8)
                                     : Color(hex: 0xFC466B).opacity(0.8))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(session.formattedDuration)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))

                Text(timeString(from: session.date))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
        .environmentObject(TimeManager())
}
