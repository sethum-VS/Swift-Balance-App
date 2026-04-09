//
//  ContentView.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-07.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var timeManager: TimeManager

    var body: some View {
        ZStack {
            // MARK: - Background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 32) {

                // MARK: - Header
                headerView

                Spacer()

                // MARK: - Clock Ring
                clockView

                Spacer()

                // MARK: - Controls
                controlButtons

                Spacer().frame(height: 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
        .preferredColorScheme(.dark)
        .alert("Action Denied", isPresented: $timeManager.showZeroBalanceError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please top up the app first.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Balance")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Live balance badge
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(balanceAccentColor)
                Text(timeManager.formattedBalance)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                Text("CR")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(balanceAccentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Clock

    private var clockView: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [ringColor.opacity(0.6), ringColor, ringColor.opacity(0.6)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 260, height: 260)
                .shadow(color: ringColor.opacity(0.4), radius: 12)

            // Inner dark circle
            Circle()
                .fill(Color(hex: 0x1A1730))
                .frame(width: 230, height: 230)

            // Session Time
            VStack(spacing: 4) {
                Text(stateLabel)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(ringColor.opacity(0.8))

                Text(timeManager.formattedSessionTime)
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(.white)

                if timeManager.currentState != .idle {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: timeManager.currentState)
        }
        // MARK: Accessibility — clock ring
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer clock")
        .accessibilityValue("\(stateLabel). Session time \(timeManager.formattedSessionTime). Total balance \(timeManager.formattedBalance).")
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 20) {
            // Top-Up Button
            ActionButton(
                title: timeManager.currentState == .toppingUp ? "Stop" : "Top-Up",
                icon: timeManager.currentState == .toppingUp ? "stop.fill" : "plus",
                gradient: [Color(hex: 0x00C9FF), Color(hex: 0x92FE9D)],
                isActive: timeManager.currentState == .toppingUp,
                isDisabled: timeManager.currentState == .consuming,
                accessibilityLabel: timeManager.currentState == .toppingUp
                    ? "Stop top-up session"
                    : "Start top-up session"
            ) {
                timeManager.startTopUp()
            }

            // Consume Button
            ActionButton(
                title: timeManager.currentState == .consuming ? "Stop" : "Consume",
                icon: timeManager.currentState == .consuming ? "stop.fill" : "minus",
                gradient: [Color(hex: 0xFC466B), Color(hex: 0x3F5EFB)],
                isActive: timeManager.currentState == .consuming,
                isDisabled: timeManager.currentState == .toppingUp,
                accessibilityLabel: timeManager.currentState == .consuming
                    ? "Stop consume session"
                    : "Start consume session. Balance is \(timeManager.formattedBalance)."
            ) {
                timeManager.startConsume()
            }
        }
    }

    // MARK: - Computed Helpers

    private var stateLabel: String {
        switch timeManager.currentState {
        case .idle:       return "Ready"
        case .toppingUp:  return "Topping Up"
        case .consuming:  return "Consuming"
        }
    }

    private var ringColor: Color {
        switch timeManager.currentState {
        case .idle:       return Color(hex: 0x6C63FF)
        case .toppingUp:  return Color(hex: 0x00E5A0)
        case .consuming:  return Color(hex: 0xFC466B)
        }
    }

    private var balanceAccentColor: Color {
        timeManager.timeBalance > 0 ? Color(hex: 0x00E5A0) : Color(hex: 0xFC466B)
    }
}

// MARK: - Action Button Component

struct ActionButton: View {
    let title: String
    let icon: String
    let gradient: [Color]
    let isActive: Bool
    let isDisabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isActive
                            ? LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.white.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isActive
                            ? AnyShapeStyle(Color.clear)
                            : AnyShapeStyle(LinearGradient(colors: gradient.map { $0.opacity(0.4) }, startPoint: .leading, endPoint: .trailing)),
                        lineWidth: 1.5
                    )
            )
            .foregroundStyle(isActive ? .black : .white)
            .shadow(color: isActive ? gradient.first!.opacity(0.4) : .clear, radius: 10, y: 4)
            .scaleEffect(isActive ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.25), value: isActive)
        }
        .disabled(isDisabled && !isActive)
        .opacity(isDisabled && !isActive ? 0.4 : 1.0)
        // MARK: Accessibility
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8)  & 0xFF) / 255.0,
            blue:  Double( hex        & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(TimeManager())
}
