import Foundation
import UIKit
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentMode: ChatMode = .solve
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showProgressSheet = false
    @Published var progress: [ProgressTopic: Bool] = {
        var initial: [ProgressTopic: Bool] = [:]
        ProgressTopic.allCases.forEach { initial[$0] = false }
        return initial
    }()

    private var sessionId: String?
    private var originalConcept: String?
    private var awaitingExamAnswer = false
    private let apiURL = URL(string: "https://nexmath.onrender.com/api/chat")!

    func newSession() {
        messages.removeAll()
        sessionId = nil
        originalConcept = nil
        awaitingExamAnswer = false
        ProgressTopic.allCases.forEach { progress[$0] = false }
    }

    func send(message: String, image: UIImage? = nil, explainAction: ExplainAction? = nil) {
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
            isExplainResponse: false
        )
        messages.append(userMessage)

        if currentMode == .explain && explainAction == nil && !trimmed.isEmpty {
            originalConcept = trimmed
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let payload = try buildPayload(message: trimmed, image: image, explainAction: explainAction)
                let response = try await performRequest(payload: payload)
                handleResponse(response)
            } catch {
                self.errorMessage = error.localizedDescription
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

    private func buildPayload(message: String, image: UIImage?, explainAction: ExplainAction?) throws -> ChatRequest {
        var imageBase64: String?
        var imageType: String?

        if let image {
            let data = image.jpegData(compressionQuality: 0.9)
            imageBase64 = data?.base64EncodedString()
            imageType = "image/jpeg"
        }

        let examAnswer = currentMode == .exam && awaitingExamAnswer

        return ChatRequest(
            message: message,
            image: imageBase64,
            image_type: imageType,
            mode: currentMode.rawValue,
            session_id: sessionId,
            explain_action: explainAction?.rawValue,
            original_concept: originalConcept,
            plot_mode: "auto",
            show_steps: true,
            explain_style: "intuition",
            exam_answer: examAnswer ? true : nil
        )
    }

    private func performRequest(payload: ChatRequest) async throws -> ChatResponse {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoded = try JSONEncoder().encode(payload)
        request.httpBody = encoded

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let errorResponse = try? JSONDecoder().decode(ChatResponse.self, from: data)
            let message = errorResponse?.error ?? "Request failed with status \(http.statusCode)."
            throw NSError(domain: "NexMath", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(ChatResponse.self, from: data)
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
            isExplainResponse: currentMode == .explain
        )
        messages.append(assistantMessage)

        if currentMode == .exam {
            if awaitingExamAnswer {
                awaitingExamAnswer = false
            } else {
                awaitingExamAnswer = true
            }
        }

        updateProgress(from: response.response)
    }

    private func updateProgress(from text: String) {
        let lower = text.lowercased()
        for topic in ProgressTopic.allCases {
            if topic.keywords.contains(where: { lower.contains($0) }) {
                progress[topic] = true
            }
        }
    }
}

struct ChatRequest: Encodable {
    let message: String
    let image: String?
    let image_type: String?
    let mode: String
    let session_id: String?
    let explain_action: String?
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
