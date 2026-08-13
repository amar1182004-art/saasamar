"use server";

import { revalidatePath } from "next/cache";

import { merchantApi } from "@/lib/server/session-api";

export async function markNotificationRead(formData: FormData) {
  const tenantId = bounded(formData.get("tenant_id"), 80);
  const notificationId = bounded(formData.get("notification_id"), 80);
  if (!tenantId || !notificationId) return;

  await merchantApi(
    `/v1/notifications/${encodeURIComponent(notificationId)}/read`,
    tenantId,
    { method: "POST", body: JSON.stringify({}) },
  );
  revalidatePath("/merchant/notifications");
}

function bounded(value: FormDataEntryValue | null, maxLength: number) {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= maxLength ? normalized : null;
}
