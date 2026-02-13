import Foundation
import OSLog

/// Specialized errors for better user feedback
enum NetworkError: LocalizedError {
    case timeout
    case connectionFailed
    case unauthorized
    case serverError(statusCode: Int, message: String)
    case invalidResponse
    case encodingFailed
    case imageTooLarge(sizeInMB: Double)

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "The request took too long to complete. Please check your internet connection and try again."
        case .connectionFailed:
            return "Unable to connect to the server. Please check your internet connection."
        case .unauthorized:
            return "Please sign in to continue."
        case .serverError(let statusCode, let message):
            return message.isEmpty ? "Server error (\(statusCode))" : message
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .encodingFailed:
            return "Failed to prepare the request. Please try again."
        case .imageTooLarge(let sizeInMB):
            return String(format: "Image is too large (%.1f MB). Please use a smaller image or reduce quality.", sizeInMB)
        }
    }
}

/// Configuration for network requests
struct NetworkConfig {
    // Timeout values based on request type
    static let defaultTimeout: TimeInterval = 30.0
    static let imageUploadTimeout: TimeInterval = 60.0

    // Retry configuration
    static let maxRetries = 2
    static let retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]

    // Image constraints (5MB limit to prevent timeouts)
    static let maxImageSizeBytes = 5 * 1024 * 1024

    // Logging
    static let enableNetworkLogging = true
}

/// Main network service class
final class NetworkService {
    private let logger = Logger(subsystem: "com.nexmath.ios", category: "network")
    private let urlSession: URLSession
    private let apiURL: URL

    init(apiURL: URL) {
        self.apiURL = apiURL

        // Create custom URLSession with timeout configuration
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = NetworkConfig.defaultTimeout
        configuration.timeoutIntervalForResource = NetworkConfig.imageUploadTimeout
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.urlSession = URLSession(configuration: configuration)
    }

    /// Sends a chat request with automatic retry and timeout handling
    func sendChatRequest(_ request: ChatRequest) async throws -> ChatResponse {
        var lastError: Error?

        // Retry loop with exponential backoff
        for attempt in 0...NetworkConfig.maxRetries {
            do {
                if attempt > 0 {
                    let delay = pow(2.0, Double(attempt - 1)) // 1s, 2s
                    logger.info("Retrying request after \(delay)s delay (attempt \(attempt + 1)/\(NetworkConfig.maxRetries + 1))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                return try await performRequest(request, attempt: attempt + 1)
            } catch let error as NetworkError {
                lastError = error

                // Don't retry on non-retryable errors
                if case .serverError(let code, _) = error {
                    if !NetworkConfig.retryableStatusCodes.contains(code) {
                        throw error
                    }
                } else if case .timeout = error {
                    // Retry timeouts
                    continue
                } else {
                    // Don't retry encoding errors, invalid response, etc.
                    throw error
                }
            } catch {
                lastError = error
                // Retry on network-level errors (URLError)
                if let urlError = error as? URLError {
                    if urlError.code == .timedOut || urlError.code == .networkConnectionLost {
                        continue
                    }
                }
                throw error
            }
        }

        // All retries exhausted
        throw lastError ?? NetworkError.connectionFailed
    }

    /// Performs a single request attempt
    private func performRequest(_ chatRequest: ChatRequest, attempt: Int) async throws -> ChatResponse {
        let startTime = Date()

        // Determine timeout based on whether we have an image
        let timeout = chatRequest.image != nil ? NetworkConfig.imageUploadTimeout : NetworkConfig.defaultTimeout

        // Create URLRequest
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        do {
            await AuthManager.shared.ensureSignedIn()
            let token = try await AuthManager.shared.getIDToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch {
            throw NetworkError.unauthorized
        }

        // Encode payload
        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(chatRequest) else {
            logger.error("Failed to encode chat request")
            throw NetworkError.encodingFailed
        }
        request.httpBody = encoded

        // Log request details
        if NetworkConfig.enableNetworkLogging {
            let payloadSize = encoded.count
            let payloadSizeMB = Double(payloadSize) / (1024 * 1024)
            logger.info("Sending request (attempt \(attempt)): payload=\(String(format: "%.2f", payloadSizeMB))MB, timeout=\(timeout)s, hasImage=\(chatRequest.image != nil)")
        }

        // Perform request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError {
            let duration = Date().timeIntervalSince(startTime)
            logger.error("Request failed after \(String(format: "%.1f", duration))s: \(error.localizedDescription)")

            // Map URLError to NetworkError
            if error.code == .timedOut {
                throw NetworkError.timeout
            } else if error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                throw NetworkError.connectionFailed
            } else {
                throw error
            }
        }

        // Log response
        let duration = Date().timeIntervalSince(startTime)
        if NetworkConfig.enableNetworkLogging {
            let responseSizeKB = Double(data.count) / 1024
            logger.info("Received response: duration=\(String(format: "%.1f", duration))s, size=\(String(format: "%.1f", responseSizeKB))KB")
        }

        // Check HTTP status
        guard let http = response as? HTTPURLResponse else {
            logger.error("Invalid response type")
            throw NetworkError.invalidResponse
        }

        if !(200..<300).contains(http.statusCode) {
            let errorResponse = try? JSONDecoder().decode(ChatResponse.self, from: data)
            let message = errorResponse?.error ?? ""
            logger.error("HTTP error \(http.statusCode): \(message)")
            throw NetworkError.serverError(statusCode: http.statusCode, message: message)
        }

        // Decode response
        do {
            return try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            logger.error("Failed to decode response: \(error.localizedDescription)")
            throw NetworkError.invalidResponse
        }
    }
}
