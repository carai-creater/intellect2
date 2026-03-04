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

  if (!res.ok) {
    const text = await res.text();
    return NextResponse.json(
      { error: text || `Upload failed: ${res.status}` },
      { status: res.status }
    );
  }

  const data = await res.json();
  return NextResponse.json({ id: data.id, name: data.name });
}
