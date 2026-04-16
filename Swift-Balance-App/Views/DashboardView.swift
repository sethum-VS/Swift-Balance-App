//
//  DashboardView.swift
//  Swift-Balance-App
//
//  Created by GitHub Copilot on 2026-04-16.
//

import SwiftUI

struct DashboardView: View {
    @State private var showSettings: Bool = false

    var body: some View {
        NavigationStack {
            ContentView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                        }
                        .accessibilityLabel("Open Settings")
                    }
                }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(TimeManager())
        .environmentObject(AuthManager())
}
