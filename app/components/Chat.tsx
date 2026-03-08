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
const MAX_FILE_SIZE_BYTES = 4.5 * 1024 * 1024;
const MAX_FILE_SIZE_MB = "4.5";

function normalizeErrorMessage(raw: string): string {
  const s = raw.trim().toLowerCase();
  if (
    s.includes("request entity too large") ||
    s.includes("payload too large") ||
    s.includes("413")
  )
    return "ファイルが大きすぎます。小さくするか、別のファイルを選んでください。";
  if (s.includes("not valid json") || s.includes("unexpected token"))
    return "サーバーからの応答が不正です。しばらくしてから再試行してください。";
  return raw || "エラーが発生しました";
}

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
        const raw = await res.text();
        let message = res.statusText;
        try {
          const data = (raw ? JSON.parse(raw) : {}) as { error?: string } | null;
          if (data && typeof data === "object" && typeof data.error === "string")
            message = data.error;
        } catch {
          if (raw) message = raw;
        }
        throw new Error(normalizeErrorMessage(message));
      }

      const reader = res.body?.getReader();
      const decoder = new TextDecoder();
      if (!reader) throw new Error("No response body");

      let full = "";
      let streamBuffer = "";
      const assistantId = `msg-${Date.now()}`;
      setMessages((prev) => [
        ...prev,
        { id: assistantId, content: "", isUser: false, streaming: true },
      ]);

      const applySseData = (rawData: string) => {
        const raw = rawData.trim();
        if (raw === "[DONE]" || !raw) return;
        try {
          const data = JSON.parse(raw);
          if (data.conversation_id) conversationIdRef.current = data.conversation_id;
          if (typeof data.answer === "string") {
            full += data.answer;
            setMessages((prev) =>
              prev.map((m) =>
                m.id === assistantId ? { ...m, content: full, streaming: true } : m
              )
            );
            setTimeout(scrollToBottom, 0);
          }
        } catch {
          // Ignore parse errors for non-JSON SSE messages (heartbeat, metadata, etc.).
        }
      };

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          streamBuffer += decoder.decode(value, { stream: true });
          const lines = streamBuffer.split("\n");
          streamBuffer = lines.pop() || "";

          for (const line of lines) {
            const normalized = line.replace(/\r$/, "");
            if (!normalized.startsWith("data:")) continue;
            applySseData(normalized.slice(5));
          }
        }

        const trailing = streamBuffer + decoder.decode();
        if (trailing.trim().startsWith("data:")) {
          applySseData(trailing.trim().slice(5));
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
      if (file.size > MAX_FILE_SIZE_BYTES) {
        setError(
          `ファイルが大きすぎます（${MAX_FILE_SIZE_MB}MB以下）。小さくするか、別のファイルを選んでください。`
        );
        e.target.value = "";
        return;
      }
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
          const msg =
            !res.ok
              ? text || res.statusText || "アップロードに失敗しました"
              : "サーバーからの応答が不正です";
          throw new Error(normalizeErrorMessage(msg));
        }
        if (!res.ok) throw new Error(normalizeErrorMessage(data.error || text || "アップロードに失敗しました"));
        if (!data.id || typeof data.id !== "string") {
          throw new Error("アップロード結果にファイルIDが含まれていません");
        }
        fileIdRef.current = data.id;
        setMessages((prev) => [
          ...prev,
          { id: `user-${Date.now()}`, content: ANALYZE_PROMPT, isUser: true },
        ]);
        setSending(true);
        await sendToDify(ANALYZE_PROMPT, data.id, conversationIdRef.current);
      } catch (err) {
        const msg = err instanceof Error ? err.message : "アップロードに失敗しました";
        setError(normalizeErrorMessage(msg));
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
        const msg = err instanceof Error ? err.message : "送信に失敗しました";
        setError(normalizeErrorMessage(msg));
      })
      .finally(() => {
        setSending(false);
      });
  }, [input, sending, sendToDify]);

  return (
    <div className={styles.chat}>
      <div className={styles.chatToolbar}>
        <h1>ラーニングチューター</h1>
        <label
          className={`${styles.uploadBtn} ${uploading ? styles.disabled : ""}`}
        >
          <span className={styles.uploadIcon} aria-hidden>
            📎
          </span>
          教材をアップロード
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
            aria-label="閉じる"
          >
            ×
          </button>
        </div>
      )}

      {uploading && (
        <div className={styles.overlay}>
          <div className={styles.spinner} />
          <p>ドキュメントを処理中…</p>
        </div>
      )}

      <div className={styles.messages} ref={scrollRef}>
        {messages.length === 0 ? (
          <div className={styles.empty}>
            <div className={styles.emptyIcon}>📄</div>
            <p>教材をアップロードして始めましょう</p>
            <span>PDF・Word（.doc / .docx）に対応・{MAX_FILE_SIZE_MB}MB以下</span>
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
          placeholder="教材について質問…"
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
          aria-label="送信"
        >
          ↑
        </button>
      </div>
    </div>
  );
}
