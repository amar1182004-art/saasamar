import { NextRequest, NextResponse } from "next/server";

import {
  clearCookie,
  MERCHANT_MFA_COOKIE,
  MERCHANT_SESSION_COOKIE,
} from "@/lib/server/auth-cookies";
import { bearer, crystellApi } from "@/lib/server/crystell-api";

export async function POST(request: NextRequest) {
  const token = request.cookies.get(MERCHANT_SESSION_COOKIE)?.value;

  if (token) {
    await crystellApi("/v1/auth/session", {
      method: "DELETE",
      headers: bearer(token),
    }).catch(() => null);
  }

  const response = new NextResponse(null, { status: 204 });
  clearCookie(response, MERCHANT_SESSION_COOKIE);
  clearCookie(response, MERCHANT_MFA_COOKIE);
  return response;
}
