//
//  SettingsView.swift
//  Swift-Balance-App
//
//  Created by GitHub Copilot on 2026-04-16.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Form {
            Section("Account") {
                Text("You are signed in")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    authManager.signOut()
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthManager())
    }
}
