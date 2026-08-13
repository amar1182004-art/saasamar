import "server-only";

import type { NextResponse } from "next/server";

export const MERCHANT_SESSION_COOKIE = "crystell_merchant_session";
export const MERCHANT_MFA_COOKIE = "crystell_merchant_mfa_challenge";
export const CONTROL_SESSION_COOKIE = "crystell_control_session";

const secure = process.env.NODE_ENV === "production";

export function setSessionCookie(
  response: NextResponse,
  name: typeof MERCHANT_SESSION_COOKIE | typeof CONTROL_SESSION_COOKIE,
  token: string,
  expiresAt?: string | null,
) {
  const parsedExpiry = expiresAt ? new Date(expiresAt) : undefined;

  response.cookies.set({
    name,
    value: token,
    httpOnly: true,
    secure,
    sameSite: "strict",
    path: "/",
    ...(parsedExpiry && !Number.isNaN(parsedExpiry.getTime()) ? { expires: parsedExpiry } : {}),
  });
}

export function setMerchantMfaCookie(
  response: NextResponse,
  challengeToken: string,
  expiresIn: number,
) {
  response.cookies.set({
    name: MERCHANT_MFA_COOKIE,
    value: challengeToken,
    httpOnly: true,
    secure,
    sameSite: "strict",
    path: "/",
    maxAge: Math.max(30, Math.min(expiresIn, 600)),
  });
}

export function clearCookie(response: NextResponse, name: string) {
  response.cookies.set({
    name,
    value: "",
    httpOnly: true,
    secure,
    sameSite: "strict",
    path: "/",
    maxAge: 0,
  });
}
