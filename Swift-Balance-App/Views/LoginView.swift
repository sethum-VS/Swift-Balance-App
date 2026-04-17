//
//  LoginView.swift
//  Swift-Balance-App
//
//  Created by GitHub Copilot on 2026-04-14.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSignUp: Bool = false

    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private var brandGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x00C9FF), Color(hex: 0x92FE9D)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var backgroundColor: Color {
        Color(hex: 0x131313)
    }

    private var inputBackgroundColor: Color {
        Color(hex: 0x1A1A1A)
    }

    private var dividerColor: Color {
        Color.white.opacity(0.14)
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                VStack(spacing: 24) {
                    VStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(brandGradient)
                            .frame(width: 80, height: 80)
                            .overlay {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x131313))
                            }
                            .shadow(color: Color(hex: 0x00C9FF, alpha: 0.30), radius: 16, x: 0, y: 8)

                        Text("Balance")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(isSignUp ? "Create your account" : "Sign in to your dashboard")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .password }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(inputBackgroundColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .foregroundStyle(.white)

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .autocapitalization(.none)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
                            .onSubmit { submitAuth() }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(inputBackgroundColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .foregroundStyle(.white)
                    }

                    if let error = authManager.errorMessage {
                        Text(error)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color(hex: 0xFF8E8E))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }

                    Button(action: submitAuth) {
                        HStack(spacing: 10) {
                            if authManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(Color(hex: 0x131313))
                            }

                            Text(buttonTitle)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(brandGradient)
                        )
                        .foregroundStyle(Color(hex: 0x131313))
                        .shadow(color: Color(hex: 0x92FE9D, alpha: 0.25), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(authManager.isLoading || !isFormValid)
                    .opacity(authManager.isLoading || !isFormValid ? 0.50 : 1.0)

                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(dividerColor)
                            .frame(height: 1)

                        Text("OR")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.45))

                        Rectangle()
                            .fill(dividerColor)
                            .frame(height: 1)
                    }
                    .padding(.top, 2)

                    Button(action: submitGoogleAuth) {
                        HStack(spacing: 10) {
                            Text("G")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: 0x4285F4))

                            Text("Continue with Google")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.black.opacity(0.88))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(authManager.isLoading)
                    .opacity(authManager.isLoading ? 0.55 : 1.0)

                    if isSignUp {
                        Text("After sign up, verify your email before you can sign in.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(hex: 0xFDE68A))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(hex: 0x171717))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 20)

                Spacer(minLength: 18)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSignUp.toggle()
                    }
                    authManager.errorMessage = nil
                } label: {
                    Text(isSignUp ? "Already have an account? Sign in" : "Don't have an account? Sign up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: 0x92FE9D))
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
        .onTapGesture {
            focusedField = nil
        }
        .preferredColorScheme(.dark)
    }

    private var buttonTitle: String {
        if authManager.isLoading {
            return isSignUp ? "Signing Up..." : "Signing In..."
        }
        return isSignUp ? "Sign Up" : "Sign In"
    }

    private func submitAuth() {
        guard isFormValid, !authManager.isLoading else { return }
        focusedField = nil

        if isSignUp {
            Task {
                await authManager.signUp(email: email, password: password)
            }
        } else {
            authManager.signIn(email: email, password: password)
        }
    }

    private func submitGoogleAuth() {
        guard !authManager.isLoading else { return }
        focusedField = nil

        Task {
            await authManager.signInWithGoogle()
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
