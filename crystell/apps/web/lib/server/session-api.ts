import "server-only";

import { cookies } from "next/headers";

import { CONTROL_SESSION_COOKIE, MERCHANT_SESSION_COOKIE } from "@/lib/server/auth-cookies";
import { bearer, crystellApi } from "@/lib/server/crystell-api";

export async function merchantApi<T>(path: string, tenantId?: string) {
  const token = (await cookies()).get(MERCHANT_SESSION_COOKIE)?.value;
  if (!token) return null;

  return crystellApi<T>(path, {
    headers: {
      ...bearer(token),
      ...(tenantId ? { "X-Crystell-Tenant": tenantId } : {}),
    },
  });
}

export async function controlApi<T>(path: string, init: RequestInit = {}) {
  const token = (await cookies()).get(CONTROL_SESSION_COOKIE)?.value;
  if (!token) return null;

  return crystellApi<T>(path, {
    ...init,
    headers: {
      ...bearer(token),
      ...init.headers,
    },
  });
}
