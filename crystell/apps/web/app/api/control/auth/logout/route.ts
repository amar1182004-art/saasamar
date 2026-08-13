import { NextRequest, NextResponse } from "next/server";

import { clearCookie, CONTROL_SESSION_COOKIE } from "@/lib/server/auth-cookies";
import { bearer, crystellApi } from "@/lib/server/crystell-api";

export async function POST(request: NextRequest) {
  const token = request.cookies.get(CONTROL_SESSION_COOKIE)?.value;

  if (token) {
    await crystellApi("/control/v1/session", {
      method: "DELETE",
      headers: bearer(token),
    }).catch(() => null);
  }

  const response = new NextResponse(null, { status: 204 });
  clearCookie(response, CONTROL_SESSION_COOKIE);
  return response;
}
