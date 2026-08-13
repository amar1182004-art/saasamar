"use server";

import { revalidatePath } from "next/cache";

import { controlApi } from "@/lib/server/session-api";

export type ControlSupportActionState = { status: "idle" | "success" | "error"; message: string };
export const initialControlSupportState: ControlSupportActionState = { status: "idle", message: "" };

export async function replyToSupportTicket(
  _previous: ControlSupportActionState,
  formData: FormData,
): Promise<ControlSupportActionState> {
  const ticketId = field(formData, "ticket_id", 80);
  const body = field(formData, "body", 5_000);
  const reason = field(formData, "reason", 500);
  if (!ticketId || !body || !reason) return { status: "error", message: "الرسالة وسبب الإجراء مطلوبان." };

  const result = await controlApi(`/control/v1/support/tickets/${encodeURIComponent(ticketId)}/messages`, {
    method: "POST",
    body: JSON.stringify({ body, reason }),
  });
  if (!result?.ok) return { status: "error", message: controlError(result?.data, "تعذر إرسال رد الدعم.") };

  revalidatePath(`/control/support/${ticketId}`);
  revalidatePath("/control/support");
  return { status: "success", message: "تم إرسال الرد وتسجيل الإجراء في Audit Log." };
}

export async function transitionSupportTicket(
  _previous: ControlSupportActionState,
  formData: FormData,
): Promise<ControlSupportActionState> {
  const ticketId = field(formData, "ticket_id", 80);
  const status = field(formData, "status", 20);
  const reason = field(formData, "reason", 500);
  if (!ticketId || !status || !reason || !new Set(["open", "pending", "resolved", "closed"]).has(status)) {
    return { status: "error", message: "الحالة وسبب التغيير مطلوبان." };
  }

  const result = await controlApi(`/control/v1/support/tickets/${encodeURIComponent(ticketId)}`, {
    method: "PATCH",
    body: JSON.stringify({ status, reason }),
  });
  if (!result?.ok) return { status: "error", message: controlError(result?.data, "تعذر تغيير حالة التذكرة.") };

  revalidatePath(`/control/support/${ticketId}`);
  revalidatePath("/control/support");
  return { status: "success", message: "تم تحديث الحالة وتوثيق السبب." };
}

function field(formData: FormData, name: string, maxLength: number) {
  const value = formData.get(name);
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= maxLength ? normalized : null;
}

function controlError(data: unknown, fallback: string) {
  if (!data || typeof data !== "object") return fallback;
  const body = data as Record<string, unknown>;
  if (body.error === "control_plane_forbidden") return "دورك الحالي لا يسمح بتنفيذ هذه العملية.";
  return typeof body.details === "string" ? body.details : fallback;
}
