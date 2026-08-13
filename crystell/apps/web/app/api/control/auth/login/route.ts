import { NextRequest, NextResponse } from "next/server";

import { CONTROL_SESSION_COOKIE, setSessionCookie } from "@/lib/server/auth-cookies";
import { crystellApi } from "@/lib/server/crystell-api";
import {
  contentLengthExceeds,
  readObjectString,
  safeApiError,
  safeErrorStatus,
} from "@/lib/server/request-input";

type ControlLoginApiResponse = {
  token?: string;
  session?: { id: string; expires_at: string };
  user?: { id: string; email: string; role: string };
  error?: string;
};

const MAX_BODY_BYTES = 16_384;

export async function POST(request: NextRequest) {
  if (contentLengthExceeds(request.headers, MAX_BODY_BYTES)) {
    return NextResponse.json({ error: "request_too_large" }, { status: 413 });
  }

  const payload = await request.json().catch(() => null);
  const email = readObjectString(payload, "email", { maxLength: 320 });
  const password = readObjectString(payload, "password", { maxLength: 512, trim: false });
  const otp = readObjectString(payload, "otp", { maxLength: 32 });

  if (!email || !password || !otp) {
    return NextResponse.json({ error: "email_password_otp_required" }, { status: 422 });
  }

  const result = await crystellApi<ControlLoginApiResponse>("/control/v1/session", {
    method: "POST",
    body: JSON.stringify({ email, password, otp }),
  });

  if (result.ok && result.data?.token) {
    const response = NextResponse.json({ user: result.data.user ?? null }, { status: 200 });
    setSessionCookie(
      response,
      CONTROL_SESSION_COOKIE,
      result.data.token,
      result.data.session?.expires_at,
    );
    return response;
  }

  const response = NextResponse.json(
    { error: safeApiError(result.data?.error, "control_plane_authentication_failed") },
    { status: safeErrorStatus(result.status) },
  );

  if (result.retryAfter) {
    response.headers.set("Retry-After", result.retryAfter);
  }

  return response;
}
