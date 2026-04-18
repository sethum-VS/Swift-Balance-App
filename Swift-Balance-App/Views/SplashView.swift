//
//  SplashView.swift
//  Swift-Balance-App
//
//  Created by Sethum Methsanda on 2026-04-19.
//

import SwiftUI

/// Animated splash screen with a cooking-themed "Balance" intro.
struct SplashView: View {
    @Binding var isFinished: Bool

    // MARK: - Animation State

    @State private var iconScale: CGFloat = 0.3
    @State private var iconOpacity: Double = 0
    @State private var iconRotation: Double = -30
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 20
    @State private var subtitleOpacity: Double = 0
    @State private var flameScale: CGFloat = 0.6
    @State private var flameOpacity: Double = 0
    @State private var ringTrim: CGFloat = 0
    @State private var dismissOpacity: Double = 1

    // MARK: - Brand Palette

    private let backgroundColor = Color(hex: 0x131313)
    private let brandGradient = LinearGradient(
        colors: [Color(hex: 0x00C9FF), Color(hex: 0x92FE9D)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    private let accentCyan = Color(hex: 0x00C9FF)
    private let accentMint = Color(hex: 0x92FE9D)

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            // Subtle radial glow behind icon
            RadialGradient(
                colors: [accentCyan.opacity(0.08), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 200
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Animated icon container
                ZStack {
                    // Spinning ring
                    Circle()
                        .trim(from: 0, to: ringTrim)
                        .stroke(
                            brandGradient,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))

                    // Flame accent — simmering below the bolt
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: 0xFF9500), Color(hex: 0xFF2D55)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .scaleEffect(flameScale)
                        .opacity(flameOpacity)
                        .offset(y: 36)

                    // Main brand icon
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(brandGradient)
                        .frame(width: 88, height: 88)
                        .overlay {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(backgroundColor)
                        }
                        .shadow(color: accentCyan.opacity(0.35), radius: 20, x: 0, y: 8)
                        .scaleEffect(iconScale)
                        .opacity(iconOpacity)
                        .rotationEffect(.degrees(iconRotation))
                }

                // Title
                Text("Balance")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(titleOpacity)
                    .offset(y: titleOffset)

                // Subtitle
                Text("Time well spent")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .opacity(subtitleOpacity)

                Spacer()
                Spacer()
            }
        }
        .opacity(dismissOpacity)
        .preferredColorScheme(.dark)
        .onAppear {
            runAnimation()
        }
    }

    // MARK: - Animation Sequence

    private func runAnimation() {
        // Phase 1: Icon springs in (0.0s)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0)) {
            iconScale = 1.0
            iconOpacity = 1.0
            iconRotation = 0
        }

        // Phase 2: Ring draws (0.2s)
        withAnimation(.easeInOut(duration: 1.0).delay(0.2)) {
            ringTrim = 1.0
        }

        // Phase 3: Flame appears and simmers (0.4s)
        withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
            flameOpacity = 1.0
            flameScale = 1.0
        }
        // Flame pulse loop
        withAnimation(
            .easeInOut(duration: 0.6)
            .repeatForever(autoreverses: true)
            .delay(0.8)
        ) {
            flameScale = 1.15
        }

        // Phase 4: Title slides up (0.6s)
        withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
            titleOpacity = 1.0
            titleOffset = 0
        }

        // Phase 5: Subtitle fades in (0.9s)
        withAnimation(.easeOut(duration: 0.4).delay(0.9)) {
            subtitleOpacity = 1.0
        }

        // Phase 6: Dismiss after 2.2s total
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeIn(duration: 0.3)) {
                dismissOpacity = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFinished = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SplashView(isFinished: .constant(false))
}
