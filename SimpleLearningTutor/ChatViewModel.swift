//
//  ChatViewModel.swift
//  SimpleLearningTutor
//
//  Manages message state, file upload, and conversation with Dify.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let content: String
    let isUser: Bool
    var isStreaming: Bool
    
    init(id: String = UUID().uuidString, content: String, isUser: Bool, isStreaming: Bool = false) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.isStreaming = isStreaming
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isUploading: Bool = false
    @Published var isSending: Bool = false
    @Published var uploadError: String?
    @Published var chatError: String?
    
    private let dify = DifyManager()
    private var conversationId: String?
    private var currentUploadedFileId: String?
    
    static let analyzeDocumentPrompt = "Analyze this document."
    
    var hasUploadedDocument: Bool {
        currentUploadedFileId != nil
    }
    
    // MARK: - Upload
    
    func uploadDocument(from url: URL) async {
        uploadError = nil
        isUploading = true
        defer { isUploading = false }
        
        do {
            let fileId = try await dify.uploadFile(fileURL: url)
            currentUploadedFileId = fileId
            await startDocumentSession(fileId: fileId)
        } catch {
            uploadError = error.localizedDescription
        }
    }
    
    /// Starts the learning session by sending a hidden "analyze" message to Dify.
    private func startDocumentSession(fileId: String) async {
        isSending = true
        chatError = nil
        
        let assistantMessageId = UUID().uuidString
        let placeholder = ChatMessage(id: assistantMessageId, content: "", isUser: false, isStreaming: true)
        messages.append(placeholder)
        
        var fullAnswer = ""
        
        do {
            try await dify.sendChatMessage(
                query: Self.analyzeDocumentPrompt,
                conversationId: conversationId,
                fileId: fileId,
                onChunk: { chunk in
                    fullAnswer += chunk
                    self.updateStreamingMessage(id: assistantMessageId, content: fullAnswer)
                },
                onConversationId: { id in
                    self.conversationId = id
                }
            )
            self.finalizeStreamingMessage(id: assistantMessageId)
        } catch {
            chatError = error.localizedDescription
            self.updateStreamingMessage(id: assistantMessageId, content: fullAnswer.isEmpty ? "Sorry, something went wrong." : fullAnswer)
            self.finalizeStreamingMessage(id: assistantMessageId)
        }
        
        isSending = false
    }
    
    private func updateStreamingMessage(id: String, content: String) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx] = ChatMessage(id: id, content: content, isUser: false, isStreaming: true)
        }
    }
    
    private func finalizeStreamingMessage(id: String) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx] = ChatMessage(id: id, content: messages[idx].content, isUser: false, isStreaming: false)
        }
    }
    
    // MARK: - Send message
    
    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        
        inputText = ""
        let userMsg = ChatMessage(content: text, isUser: true)
        messages.append(userMsg)
        
        isSending = true
        chatError = nil
        
        let assistantMessageId = UUID().uuidString
        messages.append(ChatMessage(id: assistantMessageId, content: "", isUser: false, isStreaming: true))
        
        var fullAnswer = ""
        let fileId = currentUploadedFileId
        let convId = conversationId
        
        Task {
            do {
                try await dify.sendChatMessage(
                    query: text,
                    conversationId: convId,
                    fileId: fileId,
                    onChunk: { chunk in
                        fullAnswer += chunk
                        await MainActor.run {
                            self.updateStreamingMessage(id: assistantMessageId, content: fullAnswer)
                        }
                    },
                    onConversationId: { id in
                        Task { @MainActor in self.conversationId = id }
                    }
                )
                await MainActor.run { self.finalizeStreamingMessage(id: assistantMessageId) }
            } catch {
                await MainActor.run {
                    self.chatError = error.localizedDescription
                    self.updateStreamingMessage(id: assistantMessageId, content: fullAnswer.isEmpty ? error.localizedDescription : fullAnswer)
                    self.finalizeStreamingMessage(id: assistantMessageId)
                }
            }
            await MainActor.run { self.isSending = false }
        }
    }
    
    func clearError() {
        uploadError = nil
        chatError = nil
    }
    
    func resetSession() {
        conversationId = nil
        currentUploadedFileId = nil
        messages = []
        inputText = ""
        uploadError = nil
        chatError = nil
    }
}
