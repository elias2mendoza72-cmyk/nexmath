import Foundation
import UIKit
import Combine
import OSLog

enum AppConfig {
    static var apiBaseURL: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "https://nexmath.onrender.com"
        let value = (raw?.isEmpty == false) ? raw! : fallback
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    static var apiChatURL: URL {
        URL(string: "\(apiBaseURL)/api/chat")!
    }
}
import SwiftData

@MainActor
final class ProgressState: ObservableObject {
    @Published var progress: [ProgressTopic: Bool] = {
        var initial: [ProgressTopic: Bool] = [:]
        ProgressTopic.allCases.forEach {
            initial[$0] = UserDefaults.standard.bool(forKey: "progress_\($0.rawValue)")
        }
        return initial
    }()
    @Published var showProgressSheet = false
    @Published var currentStreak: Int = UserDefaults.standard.integer(forKey: "currentStreak")

    func update(from text: String) {
        let lower = text.lowercased()
        for topic in ProgressTopic.allCases {
            if topic.keywords.contains(where: { lower.contains($0) }) {
                progress[topic] = true
                UserDefaults.standard.set(true, forKey: "progress_\(topic.rawValue)")
            }
        }
    }

    func updateStreak() {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()
        let lastDateString = UserDefaults.standard.string(forKey: "lastActiveDate") ?? ""

        if let lastDate = formatter.date(from: lastDateString) {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
            if Calendar.current.isDate(lastDate, inSameDayAs: today) {
                return
            } else if Calendar.current.isDate(lastDate, inSameDayAs: yesterday) {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }

        UserDefaults.standard.set(currentStreak, forKey: "currentStreak")
        UserDefaults.standard.set(formatter.string(from: today), forKey: "lastActiveDate")
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentMode: ChatMode = .solve
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSuccessCheckmark = false

    @Published var progressState = ProgressState()
    @Published var explainStyle: ExplainStyle = .standard
    @Published var examCorrect = 0
    @Published var examTotal = 0
    @Published var showDailyChallenge = false
    @Published var lastFailedMessage: String?
    @Published var lastFailedImage: UIImage?

    private var sessionId: String?
    private var originalConcept: String?
    @Published var awaitingExamAnswer = false
    private var currentSessionId: UUID?
    // TODO: Replace with your Firebase Cloud Function URL after deploying
    // Run: firebase deploy --only functions
    // The URL will look like: https://chat-XXXXXXXX.cloudfunctions.net
    private let apiURL = AppConfig.apiChatURL
    private var currentTask: Task<Void, Never>?
    private var checkmarkTask: Task<Void, Never>?
    private let networkService: NetworkService
    private let imageOptimizer = ImageOptimizer()
    private let logger = Logger(subsystem: "com.nexmath.ios", category: "chat")

    var modelContext: ModelContext?

    init() {
        self.networkService = NetworkService(apiURL: apiURL)
    }

    func newSession() {
        // Save current session before clearing
        saveCurrentSession()
        currentTask?.cancel()
        checkmarkTask?.cancel()
        showSuccessCheckmark = false

        messages.removeAll()
        sessionId = nil
        originalConcept = nil
        awaitingExamAnswer = false
        currentSessionId = nil
        examCorrect = 0
        examTotal = 0
    }

    func cancelRequest() {
        currentTask?.cancel()
        isLoading = false
        HapticManager.shared.buttonTap()
    }

    func send(message: String, image: UIImage? = nil, explainAction: ExplainAction? = nil, quizAction: QuizAction? = nil) {
        guard !isLoading else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && image == nil {
            return
        }

        let userMessage = ChatMessage(
            role: .user,
            content: trimmed.isEmpty ? "[Image]" : trimmed,
            mode: currentMode,
            isHTML: false,
            isExplainResponse: false,
            timestamp: Date()
        )
        messages.append(userMessage)
        HapticManager.shared.messageSend()
        progressState.updateStreak()

        if currentMode == .explain && explainAction == nil && !trimmed.isEmpty {
            originalConcept = trimmed
        }

        isLoading = true
        errorMessage = nil
        lastFailedMessage = nil
        lastFailedImage = nil
        currentTask?.cancel()

        currentTask = Task {
            do {
                let payload = try await buildPayload(message: trimmed, image: image, explainAction: explainAction, quizAction: quizAction)
                guard !Task.isCancelled else { return }
                let response = try await networkService.sendChatRequest(payload)
                guard !Task.isCancelled else { return }
                handleResponse(response)
            } catch let error as NetworkError {
                self.errorMessage = error.localizedDescription
                self.lastFailedMessage = trimmed
                self.lastFailedImage = image
                HapticManager.shared.error()
                logger.error("Chat request failed: \(error.localizedDescription)")
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = "An unexpected error occurred. Please try again."
                self.lastFailedMessage = trimmed
                self.lastFailedImage = image
                HapticManager.shared.error()
                logger.error("Unexpected error: \(error.localizedDescription)")
            }
            self.isLoading = false
        }
    }

    func sendExplainAction(_ action: ExplainAction) {
        let message: String
        switch action {
        case .deeper:
            message = "I want to understand this concept more deeply. Can you go into more detail?"
        case .differently:
            message = "I didn't quite understand that. Can you explain it a different way?"
        case .verify:
            message = "I'm ready to explain it back."
        }
        send(message: message, explainAction: action)
    }

    func sendQuizAction(_ action: QuizAction) {
        let message: String
        switch action {
        case .similar:
            message = "Give me another similar practice problem on the same topic."
        case .harder:
            message = "Give me a harder problem on this same topic."
        case .newTopic:
            message = "Let's move on to a different topic. Give me a new quiz question."
        }
        send(message: message, quizAction: action)
    }

    private func buildPayload(message: String, image: UIImage?, explainAction: ExplainAction?, quizAction: QuizAction? = nil) async throws -> ChatRequest {
        var imageBase64: String?
        var imageType: String?

        if let image {
            logger.info("Optimizing image for upload")
            let optimized = try imageOptimizer.optimize(image)
            imageBase64 = optimized.base64String
            imageType = optimized.mimeType
            logger.info("Image optimized: \(String(format: "%.1f", optimized.originalSizeKB))KB -> \(String(format: "%.1f", optimized.compressedSizeKB))KB")
        }

        let examAnswer = currentMode == .exam && awaitingExamAnswer

        return ChatRequest(
            message: message,
            image: imageBase64,
            image_type: imageType,
            mode: currentMode.rawValue,
            session_id: sessionId,
            explain_action: explainAction?.rawValue,
            quiz_action: quizAction?.rawValue,
            original_concept: originalConcept,
            plot_mode: "auto",
            show_steps: true,
            explain_style: explainStyle.apiValue,
            exam_answer: examAnswer ? true : nil
        )
    }

    private func handleResponse(_ response: ChatResponse) {
        if let session = response.session_id {
            sessionId = session
        }

        let assistantMessage = ChatMessage(
            role: .assistant,
            content: response.response,
            mode: currentMode,
            isHTML: true,
            isExplainResponse: currentMode == .explain,
            isQuizResponse: currentMode == .quiz,
            timestamp: Date()
        )
        messages.append(assistantMessage)

        // Show success checkmark
        showSuccessCheckmark = true
        checkmarkTask?.cancel()
        checkmarkTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            showSuccessCheckmark = false
        }

        if currentMode == .exam {
            if awaitingExamAnswer {
                // This is feedback on the user's answer — score it
                examTotal += 1
                let lower = response.response.lowercased()
                if lower.contains("correct") || lower.contains("right") || lower.contains("well done") || lower.contains("great job") {
                    examCorrect += 1
                }
                awaitingExamAnswer = false
            } else {
                awaitingExamAnswer = true
            }
        }

        updateProgress(from: response.response)
    }

    private func updateProgress(from text: String) {
        progressState.update(from: text)
    }

    // MARK: - Error Recovery

    func retryLastMessage() {
        guard let message = lastFailedMessage else { return }
        errorMessage = nil
        send(message: message, image: lastFailedImage)
    }

    func dismissError() {
        errorMessage = nil
        lastFailedMessage = nil
        lastFailedImage = nil
    }

    // MARK: - Daily Challenge

    func checkDailyChallenge() {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()
        let todayString = formatter.string(from: today)
        let lastDate = UserDefaults.standard.string(forKey: "lastChallengeDate") ?? ""
        showDailyChallenge = (lastDate != todayString)
    }

    func completeDailyChallenge() {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()
        UserDefaults.standard.set(formatter.string(from: today), forKey: "lastChallengeDate")
        showDailyChallenge = false
        send(message: DailyChallenge.todaysPrompt())
    }

    // MARK: - Bookmarks

    func toggleBookmark(for message: ChatMessage) {
        guard let modelContext else { return }
        let content = message.content
        let descriptor = FetchDescriptor<PersistedMessage>(
            predicate: #Predicate { $0.content == content }
        )
        if let persisted = try? modelContext.fetch(descriptor).first {
            persisted.isBookmarked.toggle()
            try? modelContext.save()
            // Update in-memory message
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index].isBookmarked = persisted.isBookmarked
            }
            HapticManager.shared.success()
        }
    }

    // MARK: - Persistence Methods

    func saveCurrentSession() {
        guard let modelContext = modelContext, !messages.isEmpty else { return }

        let session: ChatSession
        if let existingId = currentSessionId,
           let existing = try? modelContext.fetch(FetchDescriptor<ChatSession>(predicate: #Predicate { $0.id == existingId })).first {
            session = existing
            session.lastModifiedAt = Date()
        } else {
            let title = messages.first?.content.prefix(50).description ?? "New Session"
            session = ChatSession(
                title: String(title),
                mode: currentMode.rawValue,
                sessionId: sessionId
            )
            modelContext.insert(session)
            currentSessionId = session.id
        }

        // Clear existing messages for this session
        session.messages.removeAll()

        // Add current messages
        for message in messages {
            let persistedMessage = PersistedMessage(
                role: message.role == .user ? "user" : "assistant",
                content: message.content,
                mode: message.mode.rawValue,
                isHTML: message.isHTML,
                timestamp: message.timestamp
            )
            session.messages.append(persistedMessage)
        }

        try? modelContext.save()
    }

    func loadSession(_ session: ChatSession) {
        messages = session.messages.map { persistedMessage in
            ChatMessage(
                role: persistedMessage.role == "user" ? .user : .assistant,
                content: persistedMessage.content,
                mode: ChatMode(rawValue: persistedMessage.mode) ?? .solve,
                isHTML: persistedMessage.isHTML,
                isExplainResponse: false,
                timestamp: persistedMessage.timestamp,
                isBookmarked: persistedMessage.isBookmarked
            )
        }
        currentSessionId = session.id
        sessionId = session.sessionId
        currentMode = ChatMode(rawValue: session.mode) ?? .solve
    }
}

struct ChatRequest: Encodable {
    let message: String
    let image: String?
    let image_type: String?
    let mode: String
    let session_id: String?
    let explain_action: String?
    let quiz_action: String?
    let original_concept: String?
    let plot_mode: String
    let show_steps: Bool
    let explain_style: String
    let exam_answer: Bool?
}

struct ChatResponse: Decodable {
    let response: String
    let session_id: String?
    let error: String?
}
