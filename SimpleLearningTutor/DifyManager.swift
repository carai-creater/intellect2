//
//  DifyManager.swift
//  SimpleLearningTutor
//
//  Handles all Dify Service API calls: file upload and chat (with optional streaming).
//

import Foundation

// MARK: - Upload Response

struct DifyFileUploadResponse: Codable {
    let id: String
    let name: String?
    let size: Int?
    let extension: String?
    let mimeType: String?
    let createdAt: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, size, extension
        case mimeType = "mime_type"
        case createdAt = "created_at"
    }
}

// MARK: - Chat Request / Response

struct DifyChatRequest: Encodable {
    let query: String
    let user: String
    var conversationId: String?
    var responseMode: String
    var inputs: [String: String]?
    var files: [[String: String]]?
    
    enum CodingKeys: String, CodingKey {
        case query, user, inputs, files
        case conversationId = "conversation_id"
        case responseMode = "response_mode"
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(query, forKey: .query)
        try c.encode(user, forKey: .user)
        try c.encode(conversationId ?? "", forKey: .conversationId)
        try c.encode(responseMode, forKey: .responseMode)
        try c.encodeIfPresent(inputs, forKey: .inputs)
        try c.encodeIfPresent(files, forKey: .files)
    }
}

struct DifyChatBlockingResponse: Codable {
    let messageId: String?
    let conversationId: String?
    let answer: String?
    
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case conversationId = "conversation_id"
        case answer
    }
}

// MARK: - Errors

enum DifyError: LocalizedError {
    case invalidConfig
    case invalidURL
    case uploadFailed(String)
    case chatFailed(String)
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidConfig: return "API URL or key not configured. Edit Config.swift."
        case .invalidURL: return "Invalid request URL."
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        case .chatFailed(let msg): return "Chat failed: \(msg)"
        case .decodingFailed: return "Invalid response from server."
        }
    }
}

// MARK: - Dify Manager

@MainActor
final class DifyManager: ObservableObject {
    
    private let baseURL: String
    private let apiKey: String
    private let session: URLSession
    private static let defaultUser = "simple-learning-tutor-user"
    
    init(baseURL: String = Config.baseURL, apiKey: String = Config.apiKey) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = URLSession.shared
    }
    
    private func validatedBaseURL() throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "YOUR_DIFY_BASE_URL",
              let url = URL(string: trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed) else {
            throw DifyError.invalidConfig
        }
        return url
    }
    
    private var authHeader: String { "Bearer \(apiKey)" }
    
    // MARK: - File Upload
    
    /// Uploads a file to Dify workflow file API. Returns the file ID for use in chat/inputs.
    func uploadFile(fileURL: URL, user: String = Self.defaultUser) async throws -> String {
        let uploadURL = try validatedBaseURL().appendingPathComponent("files/upload")
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let data = try createMultipartBody(fileURL: fileURL, user: user, boundary: boundary)
        request.httpBody = data
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        
        let (responseData, response) = try await session.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw DifyError.uploadFailed("Invalid response")
        }
        
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw DifyError.uploadFailed(message)
        }
        
        let decoded = try JSONDecoder().decode(DifyFileUploadResponse.self, from: responseData)
        return decoded.id
    }
    
    private func createMultipartBody(fileURL: URL, user: String, boundary: String) throws -> Data {
        var data = Data()
        let filename = fileURL.lastPathComponent
        
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"user\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(user)\r\n".data(using: .utf8)!)
        
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        data.append(try Data(contentsOf: fileURL))
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return data
    }
    
    // MARK: - Chat (Streaming)
    
    /// Sends a chat message with optional file context (uploaded file ID in inputs). Streams chunks via callback.
    func sendChatMessage(
        query: String,
        conversationId: String?,
        user: String = Self.defaultUser,
        fileId: String? = nil,
        onChunk: @escaping (String) -> Void,
        onConversationId: ((String) -> Void)? = nil
    ) async throws {
        let url = try validatedBaseURL().appendingPathComponent("chat-messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var inputs: [String: String]? = nil
        if let fid = fileId, !fid.isEmpty {
            inputs = ["file_id": fid]
        }
        
        let body = DifyChatRequest(
            query: query,
            user: user,
            conversationId: conversationId,
            responseMode: "streaming",
            inputs: inputs,
            files: nil
        )
        request.httpBody = try JSONEncoder().encode(body)
        
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw DifyError.chatFailed("Invalid response")
        }
        
        guard (200...299).contains(http.statusCode) else {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let message = String(data: errorData, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw DifyError.chatFailed(message)
        }
        
        var buffer = ""
        var currentConversationId: String?
        
        for try await byte in bytes {
            buffer.append(Character(Unicode.Scalar(byte)))
            if buffer.hasSuffix("\n\n") {
                let lines = buffer.components(separatedBy: "\n")
                buffer = ""
                for line in lines {
                    if line.hasPrefix("data: ") {
                        let jsonStr = String(line.dropFirst(6))
                        if jsonStr == "[DONE]" || jsonStr.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                        if let data = jsonStr.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let convId = obj["conversation_id"] as? String {
                                currentConversationId = convId
                                onConversationId?(convId)
                            }
                            if let answer = obj["answer"] as? String {
                                onChunk(answer)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Chat (Blocking fallback)
    
    /// Sends a chat message in blocking mode. Use when streaming is not needed.
    func sendChatMessageBlocking(
        query: String,
        conversationId: String?,
        user: String = Self.defaultUser,
        fileId: String? = nil
    ) async throws -> (messageId: String?, conversationId: String?, answer: String) {
        let url = try validatedBaseURL().appendingPathComponent("chat-messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var inputs: [String: String]? = nil
        if let fid = fileId, !fid.isEmpty {
            inputs = ["file_id": fid]
        }
        
        let body = DifyChatRequest(
            query: query,
            user: user,
            conversationId: conversationId,
            responseMode: "blocking",
            inputs: inputs,
            files: nil
        )
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            throw DifyError.chatFailed(message)
        }
        
        let decoded = try JSONDecoder().decode(DifyChatBlockingResponse.self, from: data)
        return (decoded.messageId, decoded.conversationId, decoded.answer ?? "")
    }
}
