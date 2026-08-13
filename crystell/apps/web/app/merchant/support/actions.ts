"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { merchantApi } from "@/lib/server/session-api";
import type { SupportTicket } from "@/lib/support-types";

export type MerchantSupportActionState = {
  status: "idle" | "success" | "error";
  message: string;
};

export const initialMerchantSupportState: MerchantSupportActionState = { status: "idle", message: "" };

export async function createSupportTicket(
  _previous: MerchantSupportActionState,
  formData: FormData,
): Promise<MerchantSupportActionState> {
  const tenantId = field(formData, "tenant_id", 80);
  const storeId = field(formData, "store_id", 80);
  const subject = field(formData, "subject", 160);
  const body = field(formData, "body", 5_000);
  const priority = field(formData, "priority", 20) ?? "normal";

  if (!tenantId || !storeId || !subject || !body) {
    return { status: "error", message: "اكتب عنوان المشكلة وتفاصيلها قبل الإرسال." };
  }
  if (!new Set(["low", "normal", "high", "urgent"]).has(priority)) {
    return { status: "error", message: "درجة الأولوية غير صالحة." };
  }

  const result = await merchantApi<{ support_ticket: SupportTicket }>(
    `/v1/stores/${encodeURIComponent(storeId)}/support/tickets`,
    tenantId,
    { method: "POST", body: JSON.stringify({ subject, body, priority }) },
  );
  if (!result?.ok || !result.data?.support_ticket.id) {
    return { status: "error", message: supportError(result?.data, "تعذر فتح التذكرة الآن.") };
  }

  const ticketId = result.data.support_ticket.id;
  redirect(`/merchant/support/${encodeURIComponent(ticketId)}?tenant=${encodeURIComponent(tenantId)}&store=${encodeURIComponent(storeId)}`);
}

export async function replySupportTicket(
  _previous: MerchantSupportActionState,
  formData: FormData,
): Promise<MerchantSupportActionState> {
  const tenantId = field(formData, "tenant_id", 80);
  const storeId = field(formData, "store_id", 80);
  const ticketId = field(formData, "ticket_id", 80);
  const body = field(formData, "body", 5_000);
  const attachmentIds = formData.getAll("attachment_id").filter((value): value is string => typeof value === "string").slice(0, 10);

  if (!tenantId || !storeId || !ticketId || !body) {
    return { status: "error", message: "اكتب رسالتك قبل الإرسال." };
  }

  const result = await merchantApi<{ support_message: { id: string } }>(
    `/v1/stores/${encodeURIComponent(storeId)}/support/tickets/${encodeURIComponent(ticketId)}/messages`,
    tenantId,
    { method: "POST", body: JSON.stringify({ body, attachment_ids: attachmentIds }) },
  );
  if (!result?.ok) {
    return { status: "error", message: supportError(result?.data, "تعذر إرسال الرد الآن.") };
  }

  revalidatePath(`/merchant/support/${ticketId}`);
  revalidatePath("/merchant/support");
  return { status: "success", message: "تم إرسال رسالتك إلى فريق الدعم." };
}

function field(formData: FormData, name: string, maxLength: number) {
  const value = formData.get(name);
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= maxLength ? normalized : null;
}

function supportError(data: unknown, fallback: string) {
  if (!data || typeof data !== "object") return fallback;
  const body = data as Record<string, unknown>;
  if (body.error === "permission_forbidden") return "صلاحية حسابك لا تسمح بهذه العملية.";
  return typeof body.message === "string" ? body.message : fallback;
}
