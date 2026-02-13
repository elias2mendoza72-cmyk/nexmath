import SwiftUI
import SwiftData
import StoreKit
import FirebaseAuth

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true
    @AppStorage("dailyChallengeEnabled") private var dailyChallengeEnabled = false
    @State private var showClearConfirmation = false
    @StateObject private var authManager = AuthManager.shared
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    @State private var isSigningIn = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private var isAppleLinked: Bool {
        authManager.user?.providerData.contains(where: { $0.providerID == "apple.com" }) ?? false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.04, blue: 0.05), Color(red: 0.08, green: 0.08, blue: 0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                List {
                    Section {
                        HStack(spacing: 14) {
                            Image("NexMathLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: Color.cyan.opacity(0.3), radius: 8, x: 0, y: 2)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("NexMath")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(appVersion)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    } header: {
                        Text("About")
                    }

                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: isAppleLinked ? "apple.logo" : "person.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.95))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(isAppleLinked ? "Signed in with Apple" : "Anonymous session")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                Text(authManager.isSignedIn ? "Active" : "Not signed in")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.5))
                            }

                            Spacer()
                        }
                        .listRowBackground(Color.white.opacity(0.05))

                        if !isAppleLinked {
                            Button {
                                isSigningIn = true
                                Task {
                                    do {
                                        try await authManager.signInWithApple()
                                    } catch {
                                        authErrorMessage = error.localizedDescription
                                        showAuthError = true
                                    }
                                    isSigningIn = false
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 16))
                                    Text(isSigningIn ? "Signing in..." : "Sign in with Apple")
                                        .font(.system(size: 16, weight: .medium))
                                    Spacer()
                                }
                                .foregroundColor(.white)
                            }
                            .disabled(isSigningIn)
                            .listRowBackground(Color.white.opacity(0.05))
                        }
                    } header: {
                        Text("Account")
                    }

                    Section {
                        settingsLink(title: "Privacy Policy", icon: "hand.raised.fill", url: "https://nexmath.app/privacy")
                        settingsLink(title: "Terms of Service", icon: "doc.text.fill", url: "https://nexmath.app/terms")
                    } header: {
                        Text("Legal")
                    }

                    Section {
                        Button(action: {
                            HapticManager.shared.buttonTap()
                            requestReview()
                        }) {
                            HStack {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.95))
                                    .frame(width: 24)
                                Text("Rate NexMath")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.05))

                        ShareLink(item: URL(string: "https://apps.apple.com/app/nexmath/id0000000000")!) {
                            HStack {
                                Image(systemName: "square.and.arrow.up.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.95))
                                    .frame(width: 24)
                                Text("Share NexMath")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.05))

                        settingsLink(title: "Contact & Feedback", icon: "envelope.fill", url: "mailto:support@nexmath.app")
                    } header: {
                        Text("Support")
                    }

                    Section {
                        Toggle(isOn: $dailyChallengeEnabled) {
                            HStack(spacing: 10) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.95))
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Daily Challenge")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("Get a daily calculus problem at 9 AM")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                        }
                        .tint(Color(red: 0.35, green: 0.85, blue: 0.95))
                        .listRowBackground(Color.white.opacity(0.05))
                        .onChange(of: dailyChallengeEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    let granted = await NotificationManager.shared.requestPermission()
                                    if granted {
                                        NotificationManager.shared.scheduleDailyChallenge()
                                    } else {
                                        dailyChallengeEnabled = false
                                    }
                                }
                            } else {
                                NotificationManager.shared.cancelDailyChallenge()
                            }
                        }
                    } header: {
                        Text("Notifications")
                    }

                    Section {
                        Button(action: {
                            HapticManager.shared.buttonTap()
                            hasSeenOnboarding = false
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.95))
                                    .frame(width: 24)
                                Text("Replay Onboarding")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    } header: {
                        Text("Help")
                    }

                    Section {
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 16))
                                Text("Clear Chat History")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(.red)
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    } header: {
                        Text("Data")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("Clear Chat History", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    clearChatHistory()
                }
            } message: {
                Text("This will permanently delete all saved chat sessions and messages. This action cannot be undone.")
            }
            .alert("Sign In Failed", isPresented: $showAuthError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(authErrorMessage)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func settingsLink(title: String, icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.95))
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    private func clearChatHistory() {
        do {
            try modelContext.delete(model: ChatSession.self)
            try modelContext.delete(model: PersistedMessage.self)
            HapticManager.shared.success()
        } catch {
            print("Failed to clear chat history: \(error)")
        }
    }
}
