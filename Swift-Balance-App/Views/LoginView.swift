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

    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0B1020), Color(hex: 0x161B33), Color(hex: 0x0B1020)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x7FD8FF))
                        .padding(14)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )

                    Text("Welcome Back")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Sign in to continue your balance tracking")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }

                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))

                        TextField("name@example.com", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .password }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))

                        SecureField("Enter your password", text: $password)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
                            .onSubmit {
                                if isFormValid && !authManager.isLoading {
                                    authManager.signIn(email: email, password: password)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .foregroundStyle(.white)
                    }
                }

                if let error = authManager.errorMessage {
                    Text(error)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color(hex: 0xFF8E8E))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                Button {
                    authManager.signIn(email: email, password: password)
                } label: {
                    HStack(spacing: 10) {
                        if authManager.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.black)
                        }
                        Text(authManager.isLoading ? "Signing In..." : "Sign In")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: 0x7FD8FF), Color(hex: 0x66F3CB)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .foregroundStyle(.black)
                }
                .disabled(authManager.isLoading || !isFormValid)
                .opacity(authManager.isLoading || !isFormValid ? 0.5 : 1.0)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
