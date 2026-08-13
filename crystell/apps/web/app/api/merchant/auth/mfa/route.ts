import { NextRequest, NextResponse } from "next/server";

import {
  clearCookie,
  MERCHANT_MFA_COOKIE,
  MERCHANT_SESSION_COOKIE,
  setSessionCookie,
} from "@/lib/server/auth-cookies";
import { crystellApi } from "@/lib/server/crystell-api";
import { readObjectString, safeApiError, safeErrorStatus } from "@/lib/server/request-input";

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
  const code = readObjectString(payload, "code", { maxLength: 32 });
  const recoveryCode = readObjectString(payload, "recovery_code", { maxLength: 128 });

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
    { error: safeApiError(result.data?.error, "mfa_verification_failed") },
    { status: safeErrorStatus(result.status) },
  );

  if (result.status === 401) {
    clearCookie(response, MERCHANT_MFA_COOKIE);
  }

  return response;
}
