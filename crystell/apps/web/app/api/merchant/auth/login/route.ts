import { NextRequest, NextResponse } from "next/server";

import {
  clearCookie,
  MERCHANT_MFA_COOKIE,
  MERCHANT_SESSION_COOKIE,
  setMerchantMfaCookie,
  setSessionCookie,
} from "@/lib/server/auth-cookies";
import { crystellApi } from "@/lib/server/crystell-api";
import {
  contentLengthExceeds,
  readObjectString,
  safeApiError,
  safeErrorStatus,
} from "@/lib/server/request-input";

type MerchantLoginApiResponse = {
  token?: string;
  expires_at?: string;
  user?: { id: string; email: string };
  error?: string;
  challenge_token?: string;
  expires_in?: number;
};

const MAX_BODY_BYTES = 16_384;

export async function POST(request: NextRequest) {
  if (contentLengthExceeds(request.headers, MAX_BODY_BYTES)) {
    return NextResponse.json({ error: "request_too_large" }, { status: 413 });
  }

  const payload = await request.json().catch(() => null);
  const email = readObjectString(payload, "email", { maxLength: 320 });
  const password = readObjectString(payload, "password", { maxLength: 512, trim: false });

  if (!email || !password) {
    return NextResponse.json({ error: "email_and_password_required" }, { status: 422 });
  }

  const result = await crystellApi<MerchantLoginApiResponse>("/v1/auth/session", {
    method: "POST",
    body: JSON.stringify({ email, password }),
  });

  if (
    result.status === 428 &&
    result.data?.error === "mfa_required" &&
    result.data.challenge_token &&
    typeof result.data.expires_in === "number"
  ) {
    const response = NextResponse.json({ error: "mfa_required", mfa_required: true }, { status: 428 });
    clearCookie(response, MERCHANT_SESSION_COOKIE);
    setMerchantMfaCookie(response, result.data.challenge_token, result.data.expires_in);
    return response;
  }

  if (result.ok && result.data?.token) {
    const response = NextResponse.json({ user: result.data.user ?? null }, { status: 200 });
    setSessionCookie(response, MERCHANT_SESSION_COOKIE, result.data.token, result.data.expires_at);
    clearCookie(response, MERCHANT_MFA_COOKIE);
    return response;
  }

  const response = NextResponse.json(
    { error: safeApiError(result.data?.error, "merchant_authentication_failed") },
    { status: safeErrorStatus(result.status) },
  );

  if (result.retryAfter) {
    response.headers.set("Retry-After", result.retryAfter);
  }

  return response;
}
