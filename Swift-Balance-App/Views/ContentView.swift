//
//  ContentView.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-07.
//

import SwiftUI

/// Root view — a three-tab layout housing Timer, History, and Configuration.
struct ContentView: View {
    @EnvironmentObject var timeManager: TimeManager
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TimerView()
                .tabItem {
                    Image(systemName: "timer")
                    Text("Timer")
                }
                .tag(0)

            HistoryView()
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("History")
                }
                .tag(1)

            ConfigurationView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(2)
        }
        .tint(Color(hex: 0x6C63FF))
        .preferredColorScheme(.dark)
        .alert("Out of Time!", isPresented: $timeManager.showTopUpWarning) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("You have run out of earned time. Please start a Top-Up activity to earn more.")
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(TimeManager())
}
