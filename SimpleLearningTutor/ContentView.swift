//
//  ContentView.swift
//  SimpleLearningTutor
//
//  Main layout: sidebar on macOS, navigation on iOS; chat + upload.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    #if os(macOS)
    @State private var selectedDocumentURL: URL?
    #endif
    #if os(iOS)
    @State private var showDocumentPicker = false
    #endif
    
    var body: some View {
        Group {
            #if os(macOS)
            macLayout
            #else
            iosLayout
            #endif
        }
        .alert("Upload Error", isPresented: .constant(viewModel.uploadError != nil)) {
            Button("OK") { viewModel.clearError() }
        } message: {
            if let msg = viewModel.uploadError { Text(msg) }
        }
        .alert("Chat Error", isPresented: .constant(viewModel.chatError != nil)) {
            Button("OK") { viewModel.clearError() }
        } message: {
            if let msg = viewModel.chatError { Text(msg) }
        }
        .overlay {
            if viewModel.isUploading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Processing document...")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerRepresentable(
                onPick: { url in
                    showDocumentPicker = false
                    Task { await viewModel.uploadDocument(from: url) }
                },
                onDismiss: { showDocumentPicker = false }
            )
        }
        #endif
    }
    
    #if os(macOS)
    private var macLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            chatArea
        }
    }
    
    private var sidebar: some View {
        List {
            Section {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            Section {
                uploadButton
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Learning Tutor")
        .frame(minWidth: 200)
    }
    #endif
    
    #if os(iOS)
    private var iosLayout: some View {
        NavigationStack {
            chatArea
                .navigationTitle("Learning Tutor")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        uploadButton
                    }
                }
        }
    }
    #endif
    
    private var chatArea: some View {
        VStack(spacing: 0) {
            messagesList
            inputBar
        }
        .background(Color(.systemGroupedBackground))
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 400)
        #endif
    }
    
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.messages) { msg in
                            ChatMessageView(message: msg)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Upload study material to get started")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("PDF or Word documents supported")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            uploadButton
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    private var uploadButton: some View {
        Button {
            openDocumentPicker()
        } label: {
            Label("Upload Study Material", systemImage: "paperclip")
        }
        .disabled(viewModel.isUploading)
    }
    
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            #if os(iOS)
            uploadButton
                .labelStyle(.iconOnly)
            #endif
            TextField("Ask about your material...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(.secondarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .lineLimit(1...6)
                .disabled(viewModel.isSending)
            
            Button {
                viewModel.sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
    
    private func openDocumentPicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .plainText]
        if let doc = UTType(filenameExtension: "docx") ?? UTType(filenameExtension: "doc") {
            panel.allowedContentTypes.append(doc)
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await viewModel.uploadDocument(from: url) }
        }
        #else
        showDocumentPicker = true
        #endif
    }
}

// MARK: - iOS Document Picker

#if os(iOS)
struct DocumentPickerRepresentable: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.pdf, .plainText]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onDismiss: onDismiss) }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onDismiss: () -> Void
        
        init(onPick: @escaping (URL) -> Void, onDismiss: @escaping () -> Void) {
            self.onPick = onPick
            self.onDismiss = onDismiss
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { onDismiss(); return }
            let shouldStop = url.startAccessingSecurityScopedResource()
            defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
            onPick(url)
            onDismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onDismiss()
        }
    }
}
#endif

</think>
Adding the iOS document-picker sheet to ContentView and fixing the implementation.
<｜tool▁calls▁begin｜><｜tool▁call▁begin｜>
StrReplace