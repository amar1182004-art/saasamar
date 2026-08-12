import { NextResponse } from "next/server";

export async function GET() {
  const apiUrl = process.env.API_INTERNAL_URL ?? "http://api:3001";

  try {
    const response = await fetch(`${apiUrl}/ready`, { cache: "no-store" });

    if (!response.ok) {
      return NextResponse.json({ service: "web", status: "not_ready" }, { status: 503 });
    }

    return NextResponse.json({ service: "web", status: "ready" });
  } catch {
    return NextResponse.json({ service: "web", status: "not_ready" }, { status: 503 });
  }
}
