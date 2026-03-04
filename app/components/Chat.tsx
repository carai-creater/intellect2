"use client";

import { useCallback, useRef, useState } from "react";
import styles from "./Chat.module.css";

type Message = {
  id: string;
  content: string;
  isUser: boolean;
  streaming?: boolean;
};

const ANALYZE_PROMPT = "Analyze this document.";

export default function Chat() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [uploading, setUploading] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const conversationIdRef = useRef<string | null>(null);
  const fileIdRef = useRef<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = useCallback(() => {
    scrollRef.current?.scrollTo({
      top: scrollRef.current.scrollHeight,
      behavior: "smooth",
    });
  }, []);

  const sendToDify = useCallback(
    async (
      query: string,
      fileId: string | null,
      conversationId: string | null
    ) => {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          query,
          conversation_id: conversationId || "",
          file_id: fileId || undefined,
        }),
      });

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error || res.statusText);
      }

      const reader = res.body?.getReader();
      const decoder = new TextDecoder();
      if (!reader) throw new Error("No response body");

      let full = "";
      const assistantId = `msg-${Date.now()}`;
      setMessages((prev) => [
        ...prev,
        { id: assistantId, content: "", isUser: false, streaming: true },
      ]);

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          const chunk = decoder.decode(value, { stream: true });
          const lines = chunk.split("\n");
          for (const line of lines) {
            if (line.startsWith("data: ")) {
              const raw = line.slice(6).trim();
              if (raw === "[DONE]" || !raw) continue;
              try {
                const data = JSON.parse(raw);
                if (data.conversation_id)
                  conversationIdRef.current = data.conversation_id;
                if (typeof data.answer === "string") {
                  full += data.answer;
                  setMessages((prev) =>
                    prev.map((m) =>
                      m.id === assistantId
                        ? { ...m, content: full, streaming: true }
                        : m
                    )
                  );
                  setTimeout(scrollToBottom, 0);
                }
              } catch {
                // ignore parse errors for partial chunks
              }
            }
          }
        }
      } finally {
        setMessages((prev) =>
          prev.map((m) =>
            m.id === assistantId
              ? { ...m, content: full, streaming: false }
              : m
          )
        );
      }
    },
    [scrollToBottom]
  );

  const handleUpload = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;
      setError(null);
      setUploading(true);
      try {
        const form = new FormData();
        form.append("file", file);
        const res = await fetch("/api/upload", { method: "POST", body: form });
        const text = await res.text();
        let data: { id?: string; error?: string } = {};
        try {
          data = text ? JSON.parse(text) : {};
        } catch {
          if (!res.ok) throw new Error(text || "Upload failed");
          throw new Error("Invalid response from server");
        }
        if (!res.ok) throw new Error(data.error || text || "Upload failed");
        fileIdRef.current = data.id;
        setMessages((prev) => [
          ...prev,
          { id: `user-${Date.now()}`, content: ANALYZE_PROMPT, isUser: true },
        ]);
        setSending(true);
        await sendToDify(ANALYZE_PROMPT, data.id, conversationIdRef.current);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Upload failed");
      } finally {
        setUploading(false);
        setSending(false);
        e.target.value = "";
      }
    },
    [sendToDify]
  );

  const handleSend = useCallback(() => {
    const text = input.trim();
    if (!text || sending) return;
    setInput("");
    setError(null);
    setMessages((prev) => [
      ...prev,
      { id: `user-${Date.now()}`, content: text, isUser: true },
    ]);
    setSending(true);
    sendToDify(text, fileIdRef.current, conversationIdRef.current)
      .catch((err) => {
        setError(err instanceof Error ? err.message : "Send failed");
      })
      .finally(() => {
        setSending(false);
      });
  }, [input, sending, sendToDify]);

  return (
    <div className={styles.chat}>
      <div className={styles.chatToolbar}>
        <h1>Learning Tutor</h1>
        <label
          className={`${styles.uploadBtn} ${uploading ? styles.disabled : ""}`}
        >
          <span className={styles.uploadIcon} aria-hidden>
            📎
          </span>
          Upload Study Material
          <input
            type="file"
            accept=".pdf,.doc,.docx"
            onChange={handleUpload}
            disabled={uploading}
            hidden
          />
        </label>
      </div>

      {error && (
        <div className={styles.errorBanner} role="alert">
          {error}
          <button
            type="button"
            onClick={() => setError(null)}
            aria-label="Dismiss"
          >
            ×
          </button>
        </div>
      )}

      {uploading && (
        <div className={styles.overlay}>
          <div className={styles.spinner} />
          <p>Processing document…</p>
        </div>
      )}

      <div className={styles.messages} ref={scrollRef}>
        {messages.length === 0 ? (
          <div className={styles.empty}>
            <div className={styles.emptyIcon}>📄</div>
            <p>Upload study material to get started</p>
            <span>PDF or Word documents supported</span>
          </div>
        ) : (
          messages.map((m) => (
            <div
              key={m.id}
              className={`${styles.bubble} ${
                m.isUser ? styles.bubbleUser : styles.bubbleAssistant
              }`}
            >
              {!m.isUser && (
                <span className={styles.bubbleIcon} aria-hidden>
                  🧠
                </span>
              )}
              <div className={styles.bubbleContent}>
                {m.content || (m.streaming ? " " : "")}
                {m.streaming && <span className={styles.cursor} />}
              </div>
            </div>
          ))
        )}
      </div>

      <div className={styles.inputBar}>
        <input
          type="text"
          className={styles.input}
          placeholder="Ask about your material…"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) =>
            e.key === "Enter" && !e.shiftKey && handleSend()
          }
          disabled={sending}
        />
        <button
          type="button"
          className={styles.sendBtn}
          onClick={handleSend}
          disabled={!input.trim() || sending}
          aria-label="Send"
        >
          ↑
        </button>
      </div>
    </div>
  );
}
