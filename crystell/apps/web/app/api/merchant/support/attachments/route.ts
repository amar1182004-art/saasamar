import { NextRequest, NextResponse } from "next/server";

import { merchantApi } from "@/lib/server/session-api";

type AttachmentRequest = {
  action?: "issue" | "complete" | "preview";
  tenantId?: string;
  storeId?: string;
  ticketId?: string;
  attachmentId?: string;
  filename?: string;
  contentType?: string;
  byteSize?: number;
};

export async function POST(request: NextRequest) {
  let input: AttachmentRequest;
  try {
    input = await request.json() as AttachmentRequest;
  } catch {
    return NextResponse.json({ error: "invalid_json", message: "الطلب غير صالح." }, { status: 400 });
  }

  const tenantId = bounded(input.tenantId, 80);
  const storeId = bounded(input.storeId, 80);
  const ticketId = bounded(input.ticketId, 80);
  if (!tenantId || !storeId || !ticketId) {
    return NextResponse.json({ error: "invalid_context", message: "سياق المتجر غير صالح." }, { status: 422 });
  }

  const base = `/v1/stores/${encodeURIComponent(storeId)}/support/tickets/${encodeURIComponent(ticketId)}/attachments`;
  let path = base;
  let body: Record<string, unknown> = {};

  if (input.action === "issue") {
    const filename = bounded(input.filename, 180);
    const contentType = bounded(input.contentType, 120);
    if (!filename || !contentType || !Number.isSafeInteger(input.byteSize) || Number(input.byteSize) <= 0) {
      return NextResponse.json({ error: "invalid_attachment", message: "بيانات الملف غير صالحة." }, { status: 422 });
    }
    body = { filename, content_type: contentType, byte_size: input.byteSize };
  } else {
    const attachmentId = bounded(input.attachmentId, 80);
    if (!attachmentId || !new Set(["complete", "preview"]).has(input.action ?? "")) {
      return NextResponse.json({ error: "invalid_action", message: "عملية المرفق غير صالحة." }, { status: 422 });
    }
    path = `${base}/${encodeURIComponent(attachmentId)}/${input.action}`;
  }

  const result = await merchantApi<Record<string, unknown>>(path, tenantId, input.action === "preview" ? {
    method: "GET",
  } : {
    method: "POST",
    body: JSON.stringify(body),
  });
  if (!result) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  return NextResponse.json(result.data ?? { error: "attachment_request_failed" }, { status: result.status });
}

function bounded(value: unknown, maxLength: number) {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= maxLength ? normalized : null;
}
