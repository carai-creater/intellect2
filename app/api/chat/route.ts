import { NextRequest } from "next/server";

const DIFY_BASE = process.env.DIFY_BASE_URL?.replace(/\/$/, "") || "";
const DIFY_API_KEY = process.env.DIFY_API_KEY || "";
const DEFAULT_USER = "simple-learning-tutor-web";

export async function POST(request: NextRequest) {
  if (!DIFY_BASE || !DIFY_API_KEY) {
    return new Response(
      JSON.stringify({ error: "DIFY_BASE_URL and DIFY_API_KEY must be set." }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const body = await request.json();
  const {
    query,
    conversation_id = "",
    user = DEFAULT_USER,
    file_id,
  } = body as {
    query: string;
    conversation_id?: string;
    user?: string;
    file_id?: string;
  };

  if (!query || typeof query !== "string") {
    return new Response(
      JSON.stringify({ error: "query is required." }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const payload: Record<string, unknown> = {
    query,
    user,
    conversation_id: conversation_id || "",
    response_mode: "streaming",
    inputs: file_id ? { file_id } : {},
  };

  const difyRes = await fetch(`${DIFY_BASE}/chat-messages`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${DIFY_API_KEY}`,
    },
    body: JSON.stringify(payload),
  });

  if (!difyRes.ok) {
    const text = await difyRes.text();
    return new Response(
      JSON.stringify({ error: text || `Chat failed: ${difyRes.status}` }),
      { status: difyRes.status, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(difyRes.body, {
    headers: {
      "Content-Type": difyRes.headers.get("Content-Type") || "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}
