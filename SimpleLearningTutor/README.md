# Simple Learning Tutor

A cross-platform SwiftUI app (iOS + macOS) that provides a clean chat interface to learn from uploaded documents via [Dify](https://dify.ai).

## Setup

1. **Configure Dify**  
   Edit `Config.swift` and set:
   - `baseURL` — your Dify Service API base URL (e.g. `https://api.dify.ai/v1` or your self-hosted URL).
   - `apiKey` — your Dify API key (from the app’s API access / publish settings).

2. **Dify app**  
   - Use a **Chat** or **Workflow** app that can accept a file (e.g. via workflow file upload).
   - If your workflow expects the uploaded file in a variable, name it `file_id`. The app sends the uploaded file ID in `inputs.file_id` for the first “Analyze this document” message and keeps that context for the session.

3. **Open in Xcode**  
   Open `SimpleLearningTutor.xcodeproj` (in the repo root), select the **SimpleLearningTutor (iOS)** or **SimpleLearningTutor (macOS)** scheme, and run.

## User flow

1. User opens the app and sees the chat + “Upload Study Material” (paperclip).
2. User uploads a PDF or Word document; the app shows a “Processing document…” overlay.
3. After upload, the app sends a hidden “Analyze this document.” message to Dify (with the file ID in `inputs` if applicable).
4. User chats with the tutor about the material; messages use streaming when available.

## File structure

- `Config.swift` — API base URL and API key (edit before run).
- `DifyManager.swift` — Dify API: file upload (`/files/upload`), chat (`/chat-messages`, streaming).
- `ChatViewModel.swift` — Message state, upload, and conversation flow.
- `ContentView.swift` — Main UI: sidebar on macOS, navigation on iOS; chat + upload.
- `ChatMessageView.swift` — Single message bubble.
- `SimpleLearningTutorApp.swift` — App entry point.

No developer settings or API configuration are shown in the UI; only chat and upload.
