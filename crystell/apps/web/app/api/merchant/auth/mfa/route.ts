import { NextRequest, NextResponse } from "next/server";

import {
  clearCookie,
  MERCHANT_MFA_COOKIE,
  MERCHANT_SESSION_COOKIE,
  setSessionCookie,
} from "@/lib/server/auth-cookies";
import { crystellApi } from "@/lib/server/crystell-api";

type MerchantMfaApiResponse = {
  token?: string;
  expires_at?: string;
  error?: string;
};

export async function POST(request: NextRequest) {
  const challengeToken = request.cookies.get(MERCHANT_MFA_COOKIE)?.value;
  if (!challengeToken) {
    return NextResponse.json({ error: "mfa_challenge_missing" }, { status: 401 });
  }

  const payload = await request.json().catch(() => null);
  const code = readOptionalString(payload, "code", 32);
  const recoveryCode = readOptionalString(payload, "recovery_code", 128);

  if (!code && !recoveryCode) {
    return NextResponse.json({ error: "mfa_code_required" }, { status: 422 });
  }

  const result = await crystellApi<MerchantMfaApiResponse>("/v1/auth/mfa/challenge", {
    method: "POST",
    body: JSON.stringify({
      challenge_token: challengeToken,
      ...(code ? { code } : {}),
      ...(recoveryCode ? { recovery_code: recoveryCode } : {}),
    }),
  });

  if (result.ok && result.data?.token) {
    const response = NextResponse.json({ authenticated: true }, { status: 200 });
    setSessionCookie(response, MERCHANT_SESSION_COOKIE, result.data.token, result.data.expires_at);
    clearCookie(response, MERCHANT_MFA_COOKIE);
    return response;
  }

  const response = NextResponse.json(
    { error: safeError(result.data?.error, "mfa_verification_failed") },
    { status: result.status >= 400 && result.status <= 599 ? result.status : 502 },
  );

  if (result.status === 401) {
    clearCookie(response, MERCHANT_MFA_COOKIE);
  }

  return response;
}

function readOptionalString(payload: unknown, key: string, maxLength: number) {
  if (!payload || typeof payload !== "object") return null;
  const value = (payload as Record<string, unknown>)[key];
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= maxLength ? trimmed : null;
}

function safeError(value: string | undefined, fallback: string) {
  return value && /^[a-z0-9_]+$/.test(value) ? value : fallback;
}
