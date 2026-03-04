import { NextRequest, NextResponse } from "next/server";

const DIFY_BASE = process.env.DIFY_BASE_URL?.replace(/\/$/, "") || "";
const DIFY_API_KEY = process.env.DIFY_API_KEY || "";
const DEFAULT_USER = "simple-learning-tutor-web";

export async function POST(request: NextRequest) {
  if (!DIFY_BASE || !DIFY_API_KEY) {
    return NextResponse.json(
      { error: "DIFY_BASE_URL and DIFY_API_KEY must be set in environment." },
      { status: 500 }
    );
  }

  const formData = await request.formData();
  const file = formData.get("file") as File | null;
  const user = (formData.get("user") as string) || DEFAULT_USER;

  if (!file) {
    return NextResponse.json({ error: "No file provided." }, { status: 400 });
  }

  const body = new FormData();
  body.append("file", file);
  body.append("user", user);

  const res = await fetch(`${DIFY_BASE}/files/upload`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${DIFY_API_KEY}`,
    },
    body,
  });

  const text = await res.text();
  if (!res.ok) {
    return NextResponse.json(
      { error: text || `Upload failed: ${res.status}` },
      { status: res.status }
    );
  }

  let data: { id?: string; name?: string };
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    return NextResponse.json(
      { error: "Invalid response from upload service" },
      { status: 502 }
    );
  }
  return NextResponse.json({ id: data.id, name: data.name });
}
