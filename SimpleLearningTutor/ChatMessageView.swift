//
//  ChatMessageView.swift
//  SimpleLearningTutor
//
//  Single message bubble in the chat (Messages/ChatGPT style).
//

import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isUser { Spacer(minLength: 48) }
            if !message.isUser {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content.isEmpty ? " " : message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isUser ? Color.accentColor : Color(.secondarySystemFill))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                
                if message.isStreaming {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.top, 2)
                }
            }
            
            if !message.isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            ChatMessageView(message: ChatMessage(content: "Hello, I'm your learning tutor.", isUser: false))
            ChatMessageView(message: ChatMessage(content: "Can you summarize chapter 2?", isUser: true))
            ChatMessageView(message: ChatMessage(content: "Sure! Chapter 2 covers...", isUser: false, isStreaming: true))
        }
    }
    .frame(height: 400)
}
