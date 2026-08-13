import { NextRequest, NextResponse } from "next/server";

import { controlApi } from "@/lib/server/session-api";

export async function POST(request: NextRequest) {
  let input: { ticketId?: string; attachmentId?: string };
  try {
    input = await request.json() as { ticketId?: string; attachmentId?: string };
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const ticketId = bounded(input.ticketId);
  const attachmentId = bounded(input.attachmentId);
  if (!ticketId || !attachmentId) return NextResponse.json({ error: "invalid_attachment" }, { status: 422 });

  const result = await controlApi<Record<string, unknown>>(
    `/control/v1/support/tickets/${encodeURIComponent(ticketId)}/attachments/${encodeURIComponent(attachmentId)}/preview`,
  );
  if (!result) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  return NextResponse.json(result.data ?? { error: "attachment_request_failed" }, { status: result.status });
}

function bounded(value: unknown) {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= 80 ? normalized : null;
}
