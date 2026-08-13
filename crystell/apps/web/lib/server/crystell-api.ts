import "server-only";

const DEFAULT_API_URL = "http://api:3000";

export const CRYSTELL_API_URL = (process.env.CRYSTELL_API_URL ?? DEFAULT_API_URL).replace(/\/$/, "");

export type ApiResult<T> = {
  status: number;
  ok: boolean;
  data: T | null;
  retryAfter: string | null;
};

export async function crystellApi<T>(
  path: string,
  init: RequestInit = {},
): Promise<ApiResult<T>> {
  if (!path.startsWith("/")) {
    throw new Error("Crystell API paths must be absolute");
  }

  const response = await fetch(`${CRYSTELL_API_URL}${path}`, {
    ...init,
    cache: "no-store",
    headers: {
      Accept: "application/json",
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...init.headers,
    },
  });

  const contentType = response.headers.get("content-type") ?? "";
  let data: T | null = null;

  if (response.status !== 204 && contentType.includes("application/json")) {
    data = (await response.json()) as T;
  }

  return {
    status: response.status,
    ok: response.ok,
    data,
    retryAfter: response.headers.get("retry-after"),
  };
}

export function bearer(token: string): HeadersInit {
  return { Authorization: `Bearer ${token}` };
}
