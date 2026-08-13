import "server-only";

export function readObjectString(
  payload: unknown,
  key: string,
  options: { maxLength: number; trim?: boolean },
) {
  if (!payload || typeof payload !== "object") return null;

  const value = (payload as Record<string, unknown>)[key];
  if (typeof value !== "string") return null;

  const normalized = options.trim === false ? value : value.trim();
  return normalized.length > 0 && normalized.length <= options.maxLength ? normalized : null;
}

export function safeApiError(value: string | undefined, fallback: string) {
  return value && /^[a-z0-9_]+$/.test(value) ? value : fallback;
}

export function safeErrorStatus(status: number) {
  return status >= 400 && status <= 599 ? status : 502;
}

export function contentLengthExceeds(headers: Headers, maxBytes: number) {
  const raw = headers.get("content-length");
  if (!raw) return false;

  const contentLength = Number(raw);
  return Number.isFinite(contentLength) && contentLength > maxBytes;
}
