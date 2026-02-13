import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.05), Color(red: 0.08, green: 0.08, blue: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.08),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 100,
                endRadius: 400
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    WelcomePage(onContinue: advancePage).tag(0)
                    ModesPage(onContinue: advancePage).tag(1)
                    PhotoPage(onContinue: advancePage).tag(2)
                    GetStartedPage(onFinish: {
                        HapticManager.shared.success()
                        hasSeenOnboarding = true
                    }).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage
                                  ? Color(red: 0.35, green: 0.85, blue: 0.95)
                                  : Color.white.opacity(0.3))
                            .frame(width: index == currentPage ? 10 : 8,
                                   height: index == currentPage ? 10 : 8)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func advancePage() {
        HapticManager.shared.buttonTap()
        withAnimation {
            currentPage += 1
        }
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    let onContinue: () -> Void
    @State private var didAppear = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image("NexMathLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.cyan.opacity(0.3), radius: 16, x: 0, y: 8)
                .scaleEffect(didAppear ? 1 : 0.8)
                .opacity(didAppear ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: didAppear)

            Text("Welcome to NexMath")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.15), value: didAppear)

            Text("Your personal calculus tutor,\npowered by AI")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.25), value: didAppear)

            Spacer()

            ContinueButton(action: onContinue)
                .opacity(didAppear ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.4), value: didAppear)
        }
        .padding(.horizontal, 32)
        .onAppear { didAppear = true }
    }
}

// MARK: - Page 2: Modes

private struct ModesPage: View {
    let onContinue: () -> Void
    @State private var didAppear = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Four Powerful Modes")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: didAppear)

            Text("Choose how you want to learn")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, 8)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.05), value: didAppear)

            ForEach(Array(ChatMode.allCases.enumerated()), id: \.element) { index, mode in
                modeRow(mode: mode)
                    .opacity(didAppear ? 1 : 0)
                    .offset(y: didAppear ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1 + Double(index) * 0.1), value: didAppear)
            }

            Spacer()

            ContinueButton(action: onContinue)
                .opacity(didAppear ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.6), value: didAppear)
        }
        .padding(.horizontal, 32)
        .onAppear { didAppear = true }
    }

    private func modeRow(mode: ChatMode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: modeIcon(for: mode))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(modeColor(for: mode))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(modeColor(for: mode).opacity(0.2))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(mode.description)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Page 3: Photo

private struct PhotoPage: View {
    let onContinue: () -> Void
    @State private var didAppear = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.15),
                                Color(red: 0.64, green: 0.39, blue: 0.96).opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "camera.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.35, green: 0.85, blue: 0.95), Color(red: 0.64, green: 0.39, blue: 0.96)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(didAppear ? 1 : 0.8)
            .opacity(didAppear ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: didAppear)

            Text("Snap a Problem")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.15), value: didAppear)

            Text("Take a photo of any calculus problem\nand get an instant solution")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.25), value: didAppear)

            Spacer()

            ContinueButton(action: onContinue)
                .opacity(didAppear ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.4), value: didAppear)
        }
        .padding(.horizontal, 32)
        .onAppear { didAppear = true }
    }
}

// MARK: - Page 4: Get Started

private struct GetStartedPage: View {
    let onFinish: () -> Void
    @State private var didAppear = false
    @StateObject private var authManager = AuthManager.shared
    @State private var isSigningIn = false
    @State private var authErrorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.35, green: 0.85, blue: 0.95), Color(red: 0.64, green: 0.39, blue: 0.96)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(didAppear ? 1 : 0.8)
                .opacity(didAppear ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: didAppear)

            Text("You're All Set")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.15), value: didAppear)

            Text("Sign in to sync progress and protect your data.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.25), value: didAppear)

            Text(authManager.isAnonymous ? "Anonymous session" : "Signed in with Apple")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white.opacity(0.5))
                .opacity(didAppear ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.3), value: didAppear)

            if let authErrorMessage {
                Text(authErrorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }

            Spacer()

            VStack(spacing: 12) {
                if authManager.isAnonymous {
                    Button {
                        isSigningIn = true
                        authErrorMessage = nil
                        Task {
                            do {
                                try await authManager.signInWithApple()
                            } catch {
                                authErrorMessage = error.localizedDescription
                            }
                            isSigningIn = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 16, weight: .semibold))
                            Text(isSigningIn ? "Signing in..." : "Sign in with Apple")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .disabled(isSigningIn)
                }

                Button(action: onFinish) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.35, green: 0.85, blue: 0.95), Color(red: 0.64, green: 0.39, blue: 0.96)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color(red: 0.64, green: 0.39, blue: 0.96).opacity(0.4), radius: 12, x: 0, y: 6)
                }
            }
            .padding(.bottom, 20)
            .opacity(didAppear ? 1 : 0)
            .offset(y: didAppear ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: didAppear)
        }
        .padding(.horizontal, 32)
        .onAppear { didAppear = true }
    }
}

// MARK: - Shared Components

private struct ContinueButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Continue")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Helpers

private func modeIcon(for mode: ChatMode) -> String {
    switch mode {
    case .solve: return "function"
    case .explain: return "lightbulb.fill"
    case .quiz: return "puzzlepiece.fill"
    case .exam: return "checkmark.seal.fill"
    }
}

private func modeColor(for mode: ChatMode) -> Color {
    switch mode {
    case .solve: return Color(red: 0.35, green: 0.85, blue: 0.95)
    case .explain: return Color(red: 0.95, green: 0.78, blue: 0.34)
    case .quiz: return Color(red: 0.53, green: 0.78, blue: 0.47)
    case .exam: return Color(red: 0.96, green: 0.58, blue: 0.32)
    }
}
