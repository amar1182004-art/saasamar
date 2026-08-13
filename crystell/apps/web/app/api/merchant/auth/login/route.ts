import { NextRequest, NextResponse } from "next/server";

import {
  clearCookie,
  MERCHANT_MFA_COOKIE,
  MERCHANT_SESSION_COOKIE,
  setMerchantMfaCookie,
  setSessionCookie,
} from "@/lib/server/auth-cookies";
import { crystellApi } from "@/lib/server/crystell-api";

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
  if (requestBodyTooLarge(request)) {
    return NextResponse.json({ error: "request_too_large" }, { status: 413 });
  }

  const payload = await request.json().catch(() => null);
  const email = readString(payload, "email", 320);
  const password = readString(payload, "password", 512);

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
    { error: safeError(result.data?.error, "merchant_authentication_failed") },
    { status: safeStatus(result.status) },
  );

  if (result.retryAfter) {
    response.headers.set("Retry-After", result.retryAfter);
  }

  return response;
}

function requestBodyTooLarge(request: NextRequest) {
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  return Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES;
}

function readString(payload: unknown, key: string, maxLength: number) {
  if (!payload || typeof payload !== "object") return null;
  const value = (payload as Record<string, unknown>)[key];
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= maxLength ? trimmed : null;
}

function safeError(value: string | undefined, fallback: string) {
  return value && /^[a-z0-9_]+$/.test(value) ? value : fallback;
}

function safeStatus(status: number) {
  return status >= 400 && status <= 599 ? status : 502;
}
