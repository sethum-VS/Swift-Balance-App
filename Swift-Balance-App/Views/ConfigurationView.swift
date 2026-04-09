//
//  ConfigurationView.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-09.
//

import SwiftUI

/// Tab 3 — manage activity profiles (add, view, delete).
struct ConfigurationView: View {
    @EnvironmentObject var timeManager: TimeManager

    // MARK: - New Profile Form State
    @State private var newProfileName: String = ""
    @State private var newProfileCategory: AppState = .toppingUp
    @State private var newProfileIcon: String = "star.fill"
    @State private var showAddSheet: Bool = false

    /// Predefined SF Symbol options for the icon picker.
    private let iconOptions: [String] = [
        "star.fill", "brain.head.profile", "figure.run", "book.fill",
        "leaf.fill", "pencil.and.outline", "music.note", "paintbrush.fill",
        "gamecontroller.fill", "play.tv.fill", "play.rectangle.fill",
        "bubble.left.and.bubble.right.fill", "cup.and.saucer.fill",
        "fork.knife", "cart.fill", "bed.double.fill"
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    // MARK: - Top-Up Profiles
                    Section {
                        ForEach(timeManager.topUpProfiles) { profile in
                            profileRow(profile, color: Color(hex: 0x00E5A0))
                        }
                        .onDelete { offsets in
                            deleteProfiles(from: timeManager.topUpProfiles, at: offsets)
                        }
                    } header: {
                        sectionHeader("Top-Up Activities", color: Color(hex: 0x00E5A0))
                    }

                    // MARK: - Consume Profiles
                    Section {
                        ForEach(timeManager.consumeProfiles) { profile in
                            profileRow(profile, color: Color(hex: 0xFC466B))
                        }
                        .onDelete { offsets in
                            deleteProfiles(from: timeManager.consumeProfiles, at: offsets)
                        }
                    } header: {
                        sectionHeader("Consume Activities", color: Color(hex: 0xFC466B))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(hex: 0x6C63FF))
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                addProfileSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
        }
    }

    // MARK: - Profile Row

    private func profileRow(_ profile: ActivityProfile, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: profile.iconName)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.12))
                )

            Text(profile.name)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.white.opacity(0.04))
    }

    // MARK: - Delete

    private func deleteProfiles(from source: [ActivityProfile], at offsets: IndexSet) {
        for index in offsets {
            let profile = source[index]
            timeManager.deleteProfile(id: profile.id)
        }
    }

    // MARK: - Add Profile Sheet

    private var addProfileSheet: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Activity Name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .textCase(.uppercase)

                        TextField("e.g. Cooking", text: $newProfileName)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .foregroundStyle(.white)
                    }

                    // Category picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .textCase(.uppercase)

                        Picker("Category", selection: $newProfileCategory) {
                            Text("Top-Up").tag(AppState.toppingUp)
                            Text("Consume").tag(AppState.consuming)
                        }
                        .pickerStyle(.segmented)
                    }

                    // Icon picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .textCase(.uppercase)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                            ForEach(iconOptions, id: \.self) { icon in
                                Button {
                                    newProfileIcon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.title3)
                                        .foregroundStyle(
                                            newProfileIcon == icon
                                                ? (newProfileCategory == .toppingUp ? Color(hex: 0x00E5A0) : Color(hex: 0xFC466B))
                                                : .white.opacity(0.4)
                                        )
                                        .frame(width: 36, height: 36)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(newProfileIcon == icon
                                                      ? Color.white.opacity(0.1)
                                                      : Color.clear)
                                        )
                                }
                            }
                        }
                    }

                    Spacer()

                    // Save button
                    Button {
                        guard !newProfileName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let profile = ActivityProfile(
                            id: UUID(),
                            name: newProfileName.trimmingCharacters(in: .whitespaces),
                            category: newProfileCategory,
                            iconName: newProfileIcon
                        )
                        timeManager.addProfile(profile)
                        newProfileName = ""
                        newProfileIcon = "star.fill"
                        showAddSheet = false
                    } label: {
                        Text("Add Activity")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        newProfileName.trimmingCharacters(in: .whitespaces).isEmpty
                                            ? AnyShapeStyle(Color.white.opacity(0.1))
                                            : AnyShapeStyle(LinearGradient(
                                                colors: [Color(hex: 0x6C63FF), Color(hex: 0x9D50BB)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ))
                                    )
                            )
                            .foregroundStyle(.white)
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showAddSheet = false }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ConfigurationView()
        .environmentObject(TimeManager())
}
