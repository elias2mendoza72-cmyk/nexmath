import SwiftUI
import PhotosUI
import WebKit
import SwiftData

struct ChatScreen: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ChatViewModel()
    @State private var draftMessage = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showImagePreview = false
    @State private var showSessions = false
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showProgressSheet = false
    @State private var showBookmarks = false
    @Query(sort: \ChatSession.lastModifiedAt, order: .reverse) private var allSessions: [ChatSession]
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        ZStack {
            // Deep background gradient
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.05), Color(red: 0.08, green: 0.08, blue: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Subtle radial gradients for depth
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

            RadialGradient(
                colors: [
                    Color(red: 0.64, green: 0.39, blue: 0.96).opacity(0.06),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 150,
                endRadius: 500
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView(
                    mode: viewModel.currentMode,
                    onProgressTap: { showProgressSheet = true },
                    onNewSession: { viewModel.newSession() },
                    onSessionsTap: { showSessions = true },
                    onSearchTap: { showSearch = true },
                    onBookmarksTap: { showBookmarks = true },
                    onSettingsTap: { showSettings = true }
                )

                if !networkMonitor.isConnected {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 14, weight: .semibold))
                        Text("No internet connection")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.85, green: 0.35, blue: 0.25).opacity(0.9))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if authManager.isAnonymous {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.95))
                        Text("Sign in with Apple to sync progress.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Text("Sign in")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                ModeSelectorView(currentMode: $viewModel.currentMode)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if viewModel.currentMode == .explain {
                    Picker("Depth", selection: $viewModel.explainStyle) {
                        ForEach(ExplainStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }

                if viewModel.currentMode == .exam && viewModel.examTotal > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        Text("\(viewModel.examCorrect)/\(viewModel.examTotal)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .padding(.top, 6)
                    .transition(.scale.combined(with: .opacity))
                }

                if viewModel.currentMode == .exam && viewModel.awaitingExamAnswer {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Your turn — submit your answer")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.25))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Divider()
                    .overlay(Color.white.opacity(0.06))
                    .padding(.top, 12)

                MessagesView(
                    messages: viewModel.messages,
                    showEmptyState: viewModel.messages.isEmpty,
                    currentMode: viewModel.currentMode,
                    isLoading: viewModel.isLoading,
                    errorMessage: viewModel.errorMessage,
                    showDailyChallenge: viewModel.showDailyChallenge,
                    lastSession: viewModel.messages.isEmpty ? allSessions.first : nil,
                    streak: viewModel.progressState.currentStreak,
                    onSuggestionTap: { prompt in
                        draftMessage = ""
                        viewModel.send(message: prompt)
                    },
                    onAcceptChallenge: { viewModel.completeDailyChallenge() },
                    onDismissChallenge: { viewModel.showDailyChallenge = false },
                    onContinueSession: { session in viewModel.loadSession(session) },
                    onToggleBookmark: { message in viewModel.toggleBookmark(for: message) },
                    onRetry: { viewModel.retryLastMessage() },
                    onDismissError: { viewModel.dismissError() }
                ) {
                    if viewModel.currentMode == .explain {
                        ExplainActionsView(
                            onDeeper: { viewModel.sendExplainAction(.deeper) },
                            onDifferent: { viewModel.sendExplainAction(.differently) },
                            onVerify: { viewModel.sendExplainAction(.verify) }
                        )
                    } else if viewModel.currentMode == .quiz {
                        QuizActionsView(
                            onSimilar: { viewModel.sendQuizAction(.similar) },
                            onHarder: { viewModel.sendQuizAction(.harder) },
                            onNewTopic: { viewModel.sendQuizAction(.newTopic) }
                        )
                    } else {
                        EmptyView()
                    }
                }

                InputBar(
                    viewModel: viewModel,
                    message: $draftMessage,
                    isLoading: viewModel.isLoading,
                    selectedImage: $selectedImage,
                    selectedItem: $selectedItem,
                    onSend: sendMessage
                )
            }
            .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
            .animation(.easeInOut(duration: 0.3), value: viewModel.awaitingExamAnswer)
            .animation(.easeInOut(duration: 0.3), value: viewModel.examTotal)
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentMode)
        }
        .sheet(isPresented: $showProgressSheet) {
            ProgressSheet(progressState: viewModel.progressState)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showSessions) {
            SessionsView(onSessionSelected: { session in
                viewModel.loadSession(session)
            })
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView()
        }
        .onAppear {
            viewModel.modelContext = modelContext
            viewModel.checkDailyChallenge()
        }
        // Errors are now shown inline via ErrorMessageView in the chat
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    showImagePreview = true
                }
            }
        }
    }

    private func sendMessage() {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = selectedImage
        guard !trimmed.isEmpty || image != nil else { return }

        draftMessage = ""
        selectedImage = nil
        selectedItem = nil
        viewModel.send(message: trimmed, image: image)
    }
}

struct HeaderView: View {
    let mode: ChatMode
    let onProgressTap: () -> Void
    let onNewSession: () -> Void
    let onSessionsTap: () -> Void
    let onSearchTap: () -> Void
    let onBookmarksTap: () -> Void
    let onSettingsTap: () -> Void

    var body: some View {
        HStack {
            Button(action: onProgressTap) {
                HStack(spacing: 8) {
                    Image("NexMathLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: Color.cyan.opacity(0.3), radius: 8, x: 0, y: 2)

                    Text("NexMath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.35, green: 0.85, blue: 0.95), Color(red: 0.64, green: 0.39, blue: 0.96)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Progress and app information")
            .accessibilityHint("Double tap to view your progress")

            Spacer()

            Menu {
                Button(action: {
                    HapticManager.shared.buttonTap()
                    onNewSession()
                }) {
                    Label("New Session", systemImage: "plus")
                }

                Button(action: {
                    HapticManager.shared.buttonTap()
                    onSessionsTap()
                }) {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

                Button(action: {
                    HapticManager.shared.buttonTap()
                    onSearchTap()
                }) {
                    Label("Search", systemImage: "magnifyingglass")
                }

                Button(action: {
                    HapticManager.shared.buttonTap()
                    onBookmarksTap()
                }) {
                    Label("Bookmarks", systemImage: "bookmark.fill")
                }

                Button(action: {
                    HapticManager.shared.buttonTap()
                    onSettingsTap()
                }) {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .accessibilityLabel("Actions menu")
            .accessibilityHint("Double tap to open session and settings options")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Color(red: 0.04, green: 0.04, blue: 0.05))
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }
}

struct ModeSelectorView: View {
    @Binding var currentMode: ChatMode
    @Namespace private var modeAnimation

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChatMode.allCases) { mode in
                Button(action: {
                    HapticManager.shared.buttonTap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        currentMode = mode
                    }
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: modeIcon(for: mode))
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(currentMode == mode ? modeColor(for: mode) : Color.white.opacity(0.6))

                        Text(mode.title)
                            .font(.system(size: 13, weight: currentMode == mode ? .semibold : .medium))
                            .foregroundStyle(currentMode == mode ? .white : Color.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if currentMode == mode {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.regularMaterial)
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(red: 0.64, green: 0.39, blue: 0.96).opacity(0.18))
                            }
                            .matchedGeometryEffect(id: "mode_background", in: modeAnimation)
                            .shadow(color: Color(red: 0.64, green: 0.39, blue: 0.96).opacity(0.3), radius: 8, x: 0, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.title) mode")
                .accessibilityHint("Double tap to switch to \(mode.title) mode. \(mode.description)")
                .accessibilityAddTraits(currentMode == mode ? [.isSelected] : [])
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

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
        case .solve: return Color(red: 0.4, green: 0.6, blue: 1.0)
        case .explain: return Color.yellow
        case .quiz: return Color(red: 0.5, green: 0.9, blue: 0.5)
        case .exam: return Color.orange
        }
    }
}

struct MessagesView<Actions: View>: View {
    let messages: [ChatMessage]
    let showEmptyState: Bool
    let currentMode: ChatMode
    let isLoading: Bool
    let errorMessage: String?
    let showDailyChallenge: Bool
    let lastSession: ChatSession?
    let streak: Int
    let onSuggestionTap: (String) -> Void
    let onAcceptChallenge: () -> Void
    let onDismissChallenge: () -> Void
    let onContinueSession: (ChatSession) -> Void
    let onToggleBookmark: ((ChatMessage) -> Void)?
    let onRetry: () -> Void
    let onDismissError: () -> Void
    let actionsView: () -> Actions

    @State private var scrollTask: Task<Void, Never>?
    @State private var showScrollToTop = false

    init(
        messages: [ChatMessage],
        showEmptyState: Bool,
        currentMode: ChatMode = .solve,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        showDailyChallenge: Bool = false,
        lastSession: ChatSession? = nil,
        streak: Int = 0,
        onSuggestionTap: @escaping (String) -> Void = { _ in },
        onAcceptChallenge: @escaping () -> Void = {},
        onDismissChallenge: @escaping () -> Void = {},
        onContinueSession: @escaping (ChatSession) -> Void = { _ in },
        onToggleBookmark: ((ChatMessage) -> Void)? = nil,
        onRetry: @escaping () -> Void = {},
        onDismissError: @escaping () -> Void = {},
        @ViewBuilder actionsView: @escaping () -> Actions
    ) {
        self.messages = messages
        self.showEmptyState = showEmptyState
        self.currentMode = currentMode
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.showDailyChallenge = showDailyChallenge
        self.lastSession = lastSession
        self.streak = streak
        self.onSuggestionTap = onSuggestionTap
        self.onAcceptChallenge = onAcceptChallenge
        self.onDismissChallenge = onDismissChallenge
        self.onContinueSession = onContinueSession
        self.onToggleBookmark = onToggleBookmark
        self.onRetry = onRetry
        self.onDismissError = onDismissError
        self.actionsView = actionsView
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if showEmptyState {
                        if showDailyChallenge {
                            DailyChallengeCard(
                                prompt: DailyChallenge.todaysPrompt(),
                                streak: streak,
                                onAccept: onAcceptChallenge,
                                onDismiss: onDismissChallenge
                            )
                        }

                        if let session = lastSession {
                            ContinueSessionCard(session: session, onContinue: onContinueSession)
                        }

                        EmptyStateView(currentMode: currentMode, onSuggestionTap: onSuggestionTap)
                    }

                    ForEach(messages) { message in
                        MessageRow(
                            message: message,
                            onToggleBookmark: onToggleBookmark != nil ? { onToggleBookmark?(message) } : nil
                        )
                        .equatable()
                    }

                    if isLoading {
                        LoadingMessageView()
                    }

                    if let error = errorMessage {
                        ErrorMessageView(
                            message: error,
                            onRetry: onRetry,
                            onDismiss: onDismissError
                        )
                    }

                    if let last = messages.last, (last.isExplainResponse || last.isQuizResponse) {
                        actionsView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .onChange(of: messages.count) { _, _ in
                // Cancel previous scroll task
                scrollTask?.cancel()

                // Debounce scroll - only execute if no new messages arrive within 0.1s
                scrollTask = Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

                    guard !Task.isCancelled else { return }
                    guard let lastId = messages.last?.id else { return }

                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .onDisappear {
                scrollTask?.cancel()
            }
            .overlay(alignment: .bottomTrailing) {
                if showScrollToTop {
                    Button {
                        HapticManager.shared.buttonTap()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            if let firstId = messages.first?.id {
                                proxy.scrollTo(firstId, anchor: .top)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.white)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 44, height: 44)
                            }
                    }
                    .padding(20)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .onChange(of: messages.count) { old, new in
                showScrollToTop = new > 5
            }
        }
    }
}

struct EmptyStateView: View {
    let currentMode: ChatMode
    let onSuggestionTap: (String) -> Void
    @State private var didAppear = false

    private var modeTitle: String {
        switch currentMode {
        case .solve: return "Solve a Problem"
        case .explain: return "Understand a Concept"
        case .quiz: return "Quiz Yourself"
        case .exam: return "Exam Practice"
        }
    }

    private var modeSubtitle: String {
        switch currentMode {
        case .solve: return "Type or snap a calculus problem for a step-by-step solution"
        case .explain: return "Ask about any calculus concept and get a clear breakdown"
        case .quiz: return "Practice with problems at your level"
        case .exam: return "Test yourself with exam-style questions and get graded"
        }
    }

    private var modeIcon: String {
        switch currentMode {
        case .solve: return "function"
        case .explain: return "lightbulb.fill"
        case .quiz: return "puzzlepiece.fill"
        case .exam: return "checkmark.seal.fill"
        }
    }

    private var modeColor: Color {
        switch currentMode {
        case .solve: return Color(red: 0.35, green: 0.85, blue: 0.95)
        case .explain: return Color(red: 0.95, green: 0.78, blue: 0.34)
        case .quiz: return Color(red: 0.53, green: 0.78, blue: 0.47)
        case .exam: return Color(red: 0.96, green: 0.58, blue: 0.32)
        }
    }

    private var suggestions: [String] {
        switch currentMode {
        case .solve:
            return ["Find the derivative of x³sin(x)", "Evaluate ∫ x² dx", "Solve: lim(x→0) sin(x)/x"]
        case .explain:
            return ["Explain the chain rule", "What is a Riemann sum?", "Why does e^(iπ) = -1?"]
        case .quiz:
            return ["Quiz me on derivatives", "Test my integration skills", "Practice L'Hôpital's rule"]
        case .exam:
            return ["Give me a limits exam", "Test me on derivatives", "Full calculus review"]
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(modeColor.opacity(0.15))
                        .frame(width: 64, height: 64)

                    Image(systemName: modeIcon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(modeColor)
                        .symbolRenderingMode(.hierarchical)
                }
                .opacity(didAppear ? 1 : 0)
                .scaleEffect(didAppear ? 1 : 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: didAppear)

                Text(modeTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(didAppear ? 1 : 0)
                    .offset(y: didAppear ? 0 : 10)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: didAppear)

                Text(modeSubtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .opacity(didAppear ? 1 : 0)
                    .offset(y: didAppear ? 0 : 10)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.15), value: didAppear)
            }
            .padding(.top, 20)

            VStack(spacing: 8) {
                Text("Try asking")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .textCase(.uppercase)
                    .tracking(1)

                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    Button(action: {
                        HapticManager.shared.buttonTap()
                        onSuggestionTap(suggestion)
                    }) {
                        Text(suggestion)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(modeColor.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(modeColor.opacity(0.15), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .opacity(didAppear ? 1 : 0)
                    .offset(y: didAppear ? 0 : 15)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.25 + Double(index) * 0.08), value: didAppear)
                }
            }
        }
        .padding(.horizontal, 16)
        .onAppear { didAppear = true }
        .id(currentMode)
    }
}

struct DailyChallengeCard: View {
    let prompt: String
    let streak: Int
    let onAccept: () -> Void
    let onDismiss: () -> Void
    @State private var didAppear = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    if streak > 0 {
                        Text("\(streak) day streak")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Text("Daily Challenge")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(prompt)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)

            Button(action: {
                HapticManager.shared.buttonTap()
                onAccept()
            }) {
                Text("Accept Challenge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.orange, Color(red: 0.96, green: 0.58, blue: 0.32)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 20)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: didAppear)
        .onAppear { didAppear = true }
    }
}

struct ContinueSessionCard: View {
    let session: ChatSession
    let onContinue: (ChatSession) -> Void

    private var modeColor: Color {
        switch session.mode.lowercased() {
        case "solve": return Color(red: 0.35, green: 0.85, blue: 0.95)
        case "explain": return Color(red: 0.95, green: 0.78, blue: 0.34)
        case "quiz": return Color(red: 0.53, green: 0.78, blue: 0.47)
        case "exam": return Color(red: 0.96, green: 0.58, blue: 0.32)
        default: return Color.gray
        }
    }

    var body: some View {
        Button(action: {
            HapticManager.shared.buttonTap()
            onContinue(session)
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue where you left off")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(session.title)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                Text(session.mode.capitalized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(modeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(modeColor.opacity(0.2)))

                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.95))
                    .font(.system(size: 20))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct MessageRow: View, Equatable {
    let message: ChatMessage
    var onToggleBookmark: (() -> Void)?
    @State private var contentHeight: CGFloat = 80
    @State private var isCapturing = false

    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.message == rhs.message
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                // Assistant avatar
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
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                        )

                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.35, green: 0.85, blue: 0.95), Color(red: 0.64, green: 0.39, blue: 0.96)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolEffect(.pulse, options: .repeat(1))
                }
                .frame(width: 32, height: 32, alignment: .top)

                HTMLMessageView(content: message.content, isQuiz: message.mode == .quiz, height: $contentHeight)
                    .frame(height: contentHeight)
                    .animation(.easeOut(duration: 0.25), value: contentHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )

                Spacer(minLength: 8)
            } else {
                Spacer(minLength: 40)

                Text(message.content)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.64, green: 0.39, blue: 0.96).opacity(0.7),
                                        Color(red: 0.52, green: 0.27, blue: 0.84).opacity(0.7)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                            .shadow(color: Color(red: 0.64, green: 0.39, blue: 0.96).opacity(0.3), radius: 12, x: 0, y: 6)
                    )
            }
        }
        .id(message.id)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .offset(y: 10)),
            removal: .opacity
        ))
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
                HapticManager.shared.success()
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }

            ShareLink(item: message.content) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            if message.role == .assistant {
                Button {
                    captureAndShareAsImage()
                } label: {
                    Label("Share as Image", systemImage: "photo")
                }
            }

            if let onToggleBookmark {
                Button {
                    onToggleBookmark()
                } label: {
                    Label(
                        message.isBookmarked ? "Remove Bookmark" : "Bookmark",
                        systemImage: message.isBookmarked ? "bookmark.fill" : "bookmark"
                    )
                }
            }
        }
    }

    private func captureAndShareAsImage() {
        let html = HTMLBuilder.buildHTML(from: message.content, isQuiz: message.mode == .quiz)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 360, height: 1))
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1)

        webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)

        // Wait for content to load, then capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                let height = (result as? CGFloat) ?? 300
                let config = WKSnapshotConfiguration()
                config.rect = CGRect(x: 0, y: 0, width: 360, height: height)

                webView.frame = CGRect(x: 0, y: 0, width: 360, height: height)
                webView.takeSnapshot(with: config) { snapshot, _ in
                    guard let snapshot else { return }

                    // Add branding footer
                    let footerHeight: CGFloat = 44
                    let totalHeight = snapshot.size.height + footerHeight
                    let renderer = UIGraphicsImageRenderer(size: CGSize(width: snapshot.size.width, height: totalHeight))

                    let branded = renderer.image { ctx in
                        // Background
                        UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1).setFill()
                        ctx.fill(CGRect(origin: .zero, size: CGSize(width: snapshot.size.width, height: totalHeight)))
                        // Snapshot
                        snapshot.draw(at: .zero)
                        // Footer text
                        let text = "Solved with NexMath" as NSString
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                            .foregroundColor: UIColor.white.withAlphaComponent(0.5)
                        ]
                        let textSize = text.size(withAttributes: attrs)
                        let textPoint = CGPoint(
                            x: (snapshot.size.width - textSize.width) / 2,
                            y: snapshot.size.height + (footerHeight - textSize.height) / 2
                        )
                        text.draw(at: textPoint, withAttributes: attrs)
                    }

                    DispatchQueue.main.async {
                        let activityVC = UIActivityViewController(activityItems: [branded], applicationActivities: nil)
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootVC = windowScene.windows.first?.rootViewController {
                            rootVC.present(activityVC, animated: true)
                        }
                    }
                }
            }
        }
    }
}

struct ExplainActionsView: View {
    let onDeeper: () -> Void
    let onDifferent: () -> Void
    let onVerify: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            actionButton(
                title: "Explain differently",
                icon: "arrow.triangle.2.circlepath",
                action: onDifferent
            )

            actionButton(
                title: "Go deeper",
                icon: "arrow.down.circle",
                action: onDeeper
            )

            actionButton(
                title: "I understand",
                icon: "checkmark.circle.fill",
                action: onVerify,
                isPrimary: true
            )
        }
        .padding(.top, 12)
    }

    private func actionButton(title: String, icon: String, action: @escaping () -> Void, isPrimary: Bool = false) -> some View {
        Button(action: {
            HapticManager.shared.buttonTap()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isPrimary ? .white : .white.opacity(0.9))
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isPrimary ? Color(red: 0.53, green: 0.78, blue: 0.47).opacity(0.12) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(isPrimary ? 0.15 : 0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct QuizActionsView: View {
    let onSimilar: () -> Void
    let onHarder: () -> Void
    let onNewTopic: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            actionButton(
                title: "More like this",
                icon: "arrow.counterclockwise",
                action: onSimilar
            )

            actionButton(
                title: "Make it harder",
                icon: "flame",
                action: onHarder
            )

            actionButton(
                title: "New topic",
                icon: "sparkles",
                action: onNewTopic,
                isPrimary: true
            )
        }
        .padding(.top, 12)
    }

    private func actionButton(title: String, icon: String, action: @escaping () -> Void, isPrimary: Bool = false) -> some View {
        Button(action: {
            HapticManager.shared.buttonTap()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isPrimary ? .white : .white.opacity(0.9))
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isPrimary ? Color(red: 0.53, green: 0.78, blue: 0.47).opacity(0.12) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(isPrimary ? 0.15 : 0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct InputBar: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var message: String
    let isLoading: Bool
    @Binding var selectedImage: UIImage?
    @Binding var selectedItem: PhotosPickerItem?
    let onSend: () -> Void

    @FocusState private var isInputFocused: Bool
    @State private var sendButtonScale: CGFloat = 1.0
    @State private var showImageSourcePicker = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false

    private var hasContent: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImage != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            if let selectedImage {
                HStack {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    Button("Remove") {
                        self.selectedImage = nil
                        self.selectedItem = nil
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 12) {
                Menu {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }

                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Image(systemName: "photo.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Add photo")
                .accessibilityHint("Double tap to take a photo or choose from library")

                TextField(
                    "",
                    text: $message,
                    prompt: Text("Ask a calculus question...")
                        .foregroundColor(.white.opacity(0.4)),
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.vertical, 4)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .focused($isInputFocused)

                Button(action: {
                    if isLoading {
                        viewModel.cancelRequest()
                    } else {
                        isInputFocused = false
                        onSend()
                    }
                }) {
                    Image(systemName: isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.35, green: 0.85, blue: 0.95), Color(red: 0.64, green: 0.39, blue: 0.96)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                        .scaleEffect(sendButtonScale)
                }
                .disabled(!isLoading && !hasContent)
                .accessibilityLabel(isLoading ? "Cancel message" : "Send message")
                .accessibilityHint(isLoading ? "Double tap to cancel" : "Double tap to send your message")
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .overlay(alignment: .trailing) {
                if viewModel.showSuccessCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 28))
                        .transition(.scale.combined(with: .opacity))
                        .padding(.trailing, 70)
                }
            }
        }
        .padding(.bottom, 8)
        .onChange(of: message) { _, _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                sendButtonScale = hasContent ? 1.1 : 1.0
            }
        }
        .onChange(of: selectedImage) { _, _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                sendButtonScale = hasContent ? 1.1 : 1.0
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(image: $selectedImage, sourceType: .camera)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    let sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct ProgressSheet: View {
    @ObservedObject var progressState: ProgressState
    @Environment(\.dismiss) private var dismiss
    @State private var didAppear = false

    private var completedCount: Int {
        progressState.progress.values.filter { $0 }.count
    }

    private var nextTopic: ProgressTopic? {
        ProgressTopic.allCases.first { progressState.progress[$0] != true }
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

                ScrollView {
                    VStack(spacing: 12) {
                        // Header stats card
                        HStack(spacing: 20) {
                            VStack(spacing: 4) {
                                Text("\(completedCount)")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color(red: 0.35, green: 0.85, blue: 0.95), Color(red: 0.64, green: 0.39, blue: 0.96)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                Text("Completed")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }

                            Divider()
                                .frame(height: 40)
                                .overlay(Color.white.opacity(0.2))

                            VStack(spacing: 4) {
                                Text("\(ProgressTopic.allCases.count - completedCount)")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white.opacity(0.4))
                                Text("Remaining")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }

                            if progressState.currentStreak > 0 {
                                Divider()
                                    .frame(height: 40)
                                    .overlay(Color.white.opacity(0.2))

                                VStack(spacing: 4) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "flame.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.orange)
                                        Text("\(progressState.currentStreak)")
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundColor(.orange)
                                    }
                                    Text("Day Streak")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .background {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.12),
                                            Color(red: 0.64, green: 0.39, blue: 0.96).opacity(0.10)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .opacity(didAppear ? 1 : 0)
                        .offset(y: didAppear ? 0 : -20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: didAppear)

                        // Up next suggestion
                        if let next = nextTopic {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 13))
                                Text("Up next: \(next.title)")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .opacity(didAppear ? 1 : 0)
                            .animation(.easeOut(duration: 0.4).delay(0.2), value: didAppear)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 13))
                                Text("All topics covered!")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .opacity(didAppear ? 1 : 0)
                            .animation(.easeOut(duration: 0.4).delay(0.2), value: didAppear)
                        }

                        // Topic rows
                        ForEach(Array(ProgressTopic.allCases.enumerated()), id: \.element) { index, topic in
                            ProgressRow(
                                topic: topic,
                                subtitle: progressSubtitle(for: topic),
                                accent: progressAccentColor(for: topic),
                                iconName: progressIconName(for: topic),
                                completed: progressState.progress[topic] == true,
                                didAppear: didAppear,
                                index: index
                            )
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Progress")
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
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { didAppear = true }
    }
}

struct ProgressRow: View {
    let topic: ProgressTopic
    let subtitle: String
    let accent: Color
    let iconName: String
    let completed: Bool
    let didAppear: Bool
    let index: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(0.3), lineWidth: 1)
                    )

                Image(systemName: iconName)
                    .foregroundStyle(accent)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(completed ? accent.opacity(0.2) : Color.white.opacity(0.05))
                    .frame(width: 32, height: 32)

                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(completed ? accent : Color.white.opacity(0.3))
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(completed ? 0.12 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 20)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.08), value: didAppear)
        .accessibilityLabel("\(topic.title)")
        .accessibilityHint("\(subtitle). \(completed ? "Completed" : "Not yet completed")")
        .accessibilityAddTraits(completed ? [.isSelected] : [])
    }
}

private func progressAccentColor(for topic: ProgressTopic) -> Color {
    switch topic {
    case .limits:
        return Color(red: 0.35, green: 0.85, blue: 0.95)
    case .continuity:
        return Color(red: 0.53, green: 0.78, blue: 0.47)
    case .derivatives:
        return Color(red: 0.64, green: 0.39, blue: 0.96)
    case .integrals:
        return Color(red: 0.96, green: 0.58, blue: 0.32)
    case .applications:
        return Color(red: 0.95, green: 0.78, blue: 0.34)
    }
}

private func progressIconName(for topic: ProgressTopic) -> String {
    switch topic {
    case .limits:
        return "arrow.right"
    case .continuity:
        return "waveform.path"
    case .derivatives:
        return "function"
    case .integrals:
        return "sum"
    case .applications:
        return "bolt.fill"
    }
}

struct LoadingMessageView: View {
    @State private var animateGradient = false
    @State private var elapsed: Int = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
                    .frame(width: 32, height: 32)

                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.35, green: 0.85, blue: 0.95), Color(red: 0.64, green: 0.39, blue: 0.96)],
                            startPoint: animateGradient ? .topLeading : .bottomTrailing,
                            endPoint: animateGradient ? .bottomTrailing : .topLeading
                        )
                    )
                    .symbolEffect(.pulse)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .scaleEffect(animateGradient ? 1.0 : 0.5)
                            .animation(
                                .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                value: animateGradient
                            )
                    }

                    Text(elapsed >= 5 ? "Thinking... \(elapsed)s" : "Thinking...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: elapsed)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )

            Spacer(minLength: 40)
        }
        .onAppear {
            animateGradient = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    elapsed += 1
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

struct ErrorMessageView: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    private var suggestion: String {
        let lower = message.lowercased()
        if lower.contains("too long") || lower.contains("timeout") {
            return "The server is taking longer than usual."
        } else if lower.contains("connect") || lower.contains("internet") {
            return "Check your internet connection."
        } else if lower.contains("server error") || lower.contains("503") || lower.contains("500") {
            return "The server is temporarily unavailable."
        } else if lower.contains("image") {
            return "Try using a smaller image."
        } else {
            return "Something went wrong."
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(suggestion)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Button(action: {
                        HapticManager.shared.buttonTap()
                        onRetry()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Retry")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.3))
                        )
                    }

                    Button(action: {
                        HapticManager.shared.buttonTap()
                        onDismiss()
                    }) {
                        Text("Dismiss")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.orange.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.orange.opacity(0.15), lineWidth: 0.5)
                    )
            )

            Spacer(minLength: 20)
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

private func progressSubtitle(for topic: ProgressTopic) -> String {
    switch topic {
    case .limits:
        return "Approach, evaluation, and indeterminate forms"
    case .continuity:
        return "Discontinuities, definitions, and tests"
    case .derivatives:
        return "Rates, slopes, and rules"
    case .integrals:
        return "Areas, antiderivatives, and accumulation"
    case .applications:
        return "Optimization and real-world modeling"
    }
}

struct HTMLMessageView: UIViewRepresentable {
    let content: String
    let isQuiz: Bool
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WebViewPool.shared.acquire()
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.startObservingTitle(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = HTMLBuilder.buildHTML(from: content, isQuiz: isQuiz)
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObservingTitle()
        WebViewPool.shared.release(webView)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLMessageView
        var lastHTML: String?
        weak var webView: WKWebView?
        private var titleObservation: NSKeyValueObservation?

        init(_ parent: HTMLMessageView) {
            self.parent = parent
        }

        func startObservingTitle(_ webView: WKWebView) {
            titleObservation = webView.observe(\.title, options: .new) { [weak self] wv, _ in
                if let title = wv.title, let height = Double(title) {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        let newHeight = max(40, height + 8)
                        if newHeight > self.parent.height {
                            self.parent.height = newHeight
                        }
                    }
                }
            }
        }

        func stopObservingTitle() {
            titleObservation?.invalidate()
            titleObservation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measureHeight(webView)
            // Re-measure after KaTeX fonts load and cause text reflow
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.measureHeight(webView)
            }
            // Second re-measure for heavy math content that reflows late
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.measureHeight(webView)
            }
        }

        private func measureHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let height = result as? Double {
                    Task { @MainActor in
                        let newHeight = max(40, height + 8)
                        if newHeight > self.parent.height {
                            self.parent.height = newHeight
                        }
                    }
                }
            }
        }
    }
}

enum HTMLBuilder {
    static func buildHTML(from markdown: String, isQuiz: Bool = false) -> String {
        let encoded = (try? JSONEncoder().encode(markdown))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""

        let quizCSS = isQuiz ? """
            .quiz-option {
              padding: 10px 14px; margin: 6px 0; border-radius: 12px;
              border: 1.5px solid rgba(255,255,255,0.15);
              background: rgba(255,255,255,0.06);
              cursor: pointer; transition: all 0.25s ease;
              -webkit-tap-highlight-color: transparent;
            }
            .quiz-option:active { transform: scale(0.97); }
            .quiz-correct { border-color: #4ade80 !important; background: rgba(74,222,128,0.15) !important; }
            .quiz-wrong { border-color: #f87171 !important; background: rgba(248,113,113,0.15) !important; }
            .quiz-disabled { pointer-events: none; opacity: 0.85; }
        """ : ""

        let quizJS = isQuiz ? """
            (function() {
              /* Step 1: Split <p> tags that contain multiple options (A-D) joined by <br> into individual divs */
              var allP = Array.from(container.querySelectorAll('p'));
              allP.forEach(function(p) {
                var html = p.innerHTML;
                /* Check if this paragraph contains multiple options like A) ... <br> B) ... */
                var parts = html.split(/<br\\s*\\/?>/i);
                var optionParts = parts.filter(function(s) { return /^\\s*[A-D]\\)\\s/.test(s.replace(/<[^>]*>/g, '')); });
                if (optionParts.length >= 2) {
                  var wrapper = document.createElement('div');
                  parts.forEach(function(part) {
                    var trimmed = part.trim();
                    if (!trimmed) return;
                    var div = document.createElement('div');
                    div.innerHTML = trimmed;
                    wrapper.appendChild(div);
                  });
                  p.parentNode.replaceChild(wrapper, p);
                }
              });

              /* Step 2: Find all text nodes/elements, collect options and answers into groups */
              var elements = Array.from(container.querySelectorAll('div, p'));
              var currentOptions = [];
              var groups = [];
              elements.forEach(function(el) {
                var text = el.textContent.trim();
                /* Skip containers that have child divs (wrapper divs) */
                if (el.children.length > 0 && el.querySelector('div')) return;
                if (/^[A-D]\\)\\s/.test(text)) {
                  currentOptions.push(el);
                }
                var answerMatch = text.match(/\\[ANSWER:\\s*([A-D])\\]/);
                if (answerMatch) {
                  el.style.display = 'none';
                  if (currentOptions.length > 0) {
                    groups.push({ options: currentOptions.slice(), answer: answerMatch[1] });
                    currentOptions = [];
                  }
                }
              });

              /* Step 3: Style options as tappable cards with click handlers */
              groups.forEach(function(group) {
                group.options.forEach(function(el) {
                  el.classList.add('quiz-option');
                  el.addEventListener('click', function() {
                    if (el.classList.contains('quiz-disabled')) return;
                    var letter = el.textContent.trim().charAt(0);
                    var isCorrect = (letter === group.answer);
                    group.options.forEach(function(opt) {
                      opt.classList.add('quiz-disabled');
                      if (opt.textContent.trim().charAt(0) === group.answer) {
                        opt.classList.add('quiz-correct');
                      }
                    });
                    if (!isCorrect) { el.classList.add('quiz-wrong'); }
                    requestAnimationFrame(function() {
                      document.title = '' + document.body.scrollHeight;
                    });
                  });
                });
              });
            })();
        """ : ""

        return """
        <!doctype html>
        <html>
        <head>
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
          <meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-inline' 'self' https://cdn.plot.ly https://cdn.plotly.com; style-src 'unsafe-inline' 'self'; font-src 'self'; img-src data: blob: https:; connect-src https://cdn.plot.ly https://cdn.plotly.com;\">
          <link rel=\"stylesheet\" href=\"katex.min.css\">
          <style>
            body { margin: 0; padding-bottom: 4px; color: #f8fafc; font: 15px -apple-system, BlinkMacSystemFont, 'Inter', 'Helvetica Neue', sans-serif; background: transparent; }
            p, li { line-height: 1.5; }
            img { max-width: 100%; border-radius: 12px; }
            code { background: rgba(255,255,255,0.08); padding: 2px 6px; border-radius: 6px; }
            pre { background: rgba(255,255,255,0.06); padding: 12px; border-radius: 12px; overflow-x: auto; }
            h1,h2,h3 { margin: 0.6em 0 0.4em; }
            .plot-container { margin: 12px 0; overflow-x: auto; border-radius: 8px; }
            .plot-container img, .plot-container svg { filter: invert(1) hue-rotate(180deg); border-radius: 8px; }
            .js-plotly-plot .plotly .main-svg { background: transparent !important; }
            .plotly .bg { fill: transparent !important; }
            \(quizCSS)
          </style>
        </head>
        <body>
          <div id=\"content\"></div>
          <script src=\"marked.min.js\"></script>
          <script src=\"katex.min.js\"></script>
          <script src=\"auto-render.min.js\"></script>
          <script>
            const raw = \(encoded);
            // Sanitize: strip dangerous HTML tags and event handlers before parsing
            // Note: <script> tags are allowed so server-rendered plots (Plotly) can execute.
            // The CSP restricts scripts to inline, self, and trusted plot CDNs only.
            const cleaned = raw
              .replace(/<(iframe|object|embed|form|input|link|meta)[^>]*>[\\s\\S]*?<\\/\\1>/gi, '')
              .replace(/<(iframe|object|embed|form|input|link|meta)[^>]*\\/?>/gi, '')
              .replace(/on\\w+=\\s*["'][^"']*["']/gi, '');
            const html = marked.parse(cleaned, { breaks: true, mangle: false, headerIds: false });
            const container = document.getElementById('content');
            container.innerHTML = html;
            renderMathInElement(container, {
              delimiters: [
                {left: '$$', right: '$$', display: true},
                {left: '$', right: '$', display: false},
                {left: '\\\\(', right: '\\\\)', display: false},
                {left: '\\\\[', right: '\\\\]', display: true}
              ]
            });
            \(quizJS)
            // Signal final height after fonts load (triggers KVO on title)
            document.fonts.ready.then(function() {
              requestAnimationFrame(function() {
                document.title = '' + document.body.scrollHeight;
              });
            });
          </script>
        </body>
        </html>
        """
    }
}
