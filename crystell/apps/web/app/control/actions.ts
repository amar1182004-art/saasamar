"use server";

import { revalidatePath } from "next/cache";

import { controlApi } from "@/lib/server/session-api";

export type ControlActionState = {
  status: "idle" | "success" | "error";
  message: string;
};

function field(formData: FormData, name: string, maxLength: number) {
  const value = formData.get(name);
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= maxLength ? normalized : null;
}

function parseJsonObject(value: string | null, maxLength: number) {
  if (!value || value.length > maxLength) throw new Error("صيغة JSON غير صالحة أو أكبر من الحد المسموح.");
  const parsed: unknown = JSON.parse(value);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("المحتوى يجب أن يكون JSON Object.");
  }
  return parsed as Record<string, unknown>;
}

function apiMessage(data: unknown, fallback: string) {
  if (!data || typeof data !== "object") return fallback;
  const body = data as Record<string, unknown>;
  if (body.error === "privilege_elevation_required") return "ارفع صلاحيات الجلسة أولًا ثم أعد المحاولة.";
  if (body.error === "control_plane_forbidden") return "دورك الحالي لا يسمح بتنفيذ هذه العملية.";
  return typeof body.details === "string" ? body.details : fallback;
}

async function authenticatedControlAction() {
  const result = await controlApi<{ user: { id: string } }>("/control/v1/me");
  return Boolean(result?.ok && result.data?.user.id);
}

export async function elevateControlSession(
  _previous: ControlActionState,
  formData: FormData,
): Promise<ControlActionState> {
  if (!(await authenticatedControlAction())) return { status: "error", message: "انتهت الجلسة. سجّل الدخول مرة أخرى." };
  const password = field(formData, "password", 512);
  const otp = field(formData, "otp", 32);
  if (!password || !otp) return { status: "error", message: "أدخل كلمة المرور ورمز MFA." };

  const result = await controlApi<{ elevated: boolean }>("/control/v1/elevation", {
    method: "POST",
    body: JSON.stringify({ password, otp }),
  });
  if (!result?.ok || !result.data?.elevated) {
    return { status: "error", message: "تعذر رفع الصلاحيات. راجع كلمة المرور ورمز MFA." };
  }

  revalidatePath("/control", "layout");
  return { status: "success", message: "تم رفع صلاحيات الجلسة مؤقتًا." };
}

export async function saveContentDraft(
  _previous: ControlActionState,
  formData: FormData,
): Promise<ControlActionState> {
  if (!(await authenticatedControlAction())) return { status: "error", message: "انتهت الجلسة. سجّل الدخول مرة أخرى." };
  const key = field(formData, "key", 120);
  const kind = field(formData, "kind", 40);
  const locale = field(formData, "locale", 10);
  const reason = field(formData, "reason", 500);
  if (!key || !kind || !locale) return { status: "error", message: "المفتاح والنوع واللغة حقول مطلوبة." };

  let content: Record<string, unknown>;
  try {
    content = parseJsonObject(field(formData, "content", 131_072), 131_072);
  } catch (error) {
    return { status: "error", message: error instanceof Error ? error.message : "صيغة المحتوى غير صالحة." };
  }

  const result = await controlApi<{ content_document: unknown }>(`/control/v1/content/${encodeURIComponent(key)}`, {
    method: "PUT",
    body: JSON.stringify({ content_document: { kind, locale, content, reason } }),
  });
  if (!result?.ok) return { status: "error", message: apiMessage(result?.data, "تعذر حفظ المسودة.") };

  revalidatePath("/control");
  revalidatePath("/control/content");
  return { status: "success", message: "تم حفظ مسودة جديدة بنجاح." };
}

export async function publishContent(
  _previous: ControlActionState,
  formData: FormData,
): Promise<ControlActionState> {
  if (!(await authenticatedControlAction())) return { status: "error", message: "انتهت الجلسة. سجّل الدخول مرة أخرى." };
  const key = field(formData, "key", 120);
  const locale = field(formData, "locale", 10);
  const reason = field(formData, "reason", 500);
  if (!key || !locale || !reason) return { status: "error", message: "اكتب سبب النشر قبل المتابعة." };

  const result = await controlApi<{ content_document: unknown }>(`/control/v1/content/${encodeURIComponent(key)}/publish`, {
    method: "POST",
    body: JSON.stringify({ publication: { locale, reason } }),
  });
  if (!result?.ok) return { status: "error", message: apiMessage(result?.data, "تعذر نشر المحتوى.") };

  revalidatePath("/control");
  revalidatePath("/control/content");
  return { status: "success", message: "تم نشر المحتوى وأصبح الإصدار الحالي Live." };
}

export async function saveFeatureFlag(
  _previous: ControlActionState,
  formData: FormData,
): Promise<ControlActionState> {
  if (!(await authenticatedControlAction())) return { status: "error", message: "انتهت الجلسة. سجّل الدخول مرة أخرى." };
  const key = field(formData, "key", 120);
  const description = field(formData, "description", 1_000);
  const rollout = field(formData, "rollout_percentage", 3);
  const reason = field(formData, "reason", 500);
  if (!key || !rollout || !reason) return { status: "error", message: "المفتاح والنسبة وسبب التغيير حقول مطلوبة." };

  const rolloutPercentage = Number(rollout);
  if (!Number.isInteger(rolloutPercentage) || rolloutPercentage < 0 || rolloutPercentage > 100) {
    return { status: "error", message: "نسبة الإطلاق يجب أن تكون رقمًا صحيحًا من 0 إلى 100." };
  }

  let config: Record<string, unknown>;
  try {
    config = parseJsonObject(field(formData, "config", 32_768) ?? "{}", 32_768);
  } catch (error) {
    return { status: "error", message: error instanceof Error ? error.message : "إعدادات العلم غير صالحة." };
  }

  const result = await controlApi<{ feature_flag: unknown }>(`/control/v1/feature-flags/${encodeURIComponent(key)}`, {
    method: "PUT",
    body: JSON.stringify({
      feature_flag: {
        description,
        enabled: formData.get("enabled") === "on",
        rollout_percentage: rolloutPercentage,
        config,
        reason,
      },
    }),
  });
  if (!result?.ok) return { status: "error", message: apiMessage(result?.data, "تعذر حفظ Feature Flag.") };

  revalidatePath("/control");
  revalidatePath("/control/feature-flags");
  return { status: "success", message: "تم تحديث Feature Flag بنجاح." };
}
