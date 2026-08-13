"use client";

import { useActionState } from "react";

import { elevateControlSession, type ControlActionState } from "@/app/control/actions";
import { ActionFeedback } from "@/components/control/action-feedback";

const initialState: ControlActionState = { status: "idle", message: "" };

export function ElevationForm() {
  const [state, action, pending] = useActionState(elevateControlSession, initialState);

  return (
    <form action={action} className="compact-form elevation-form">
      <div className="form-title">
        <strong>رفع الصلاحيات</strong>
        <small>مطلوب للنشر وتغيير الإطلاقات الحية، ويستمر لفترة قصيرة فقط.</small>
      </div>
      <div className="form-row">
        <label>كلمة المرور<input name="password" type="password" autoComplete="current-password" maxLength={512} required /></label>
        <label>رمز MFA<input name="otp" inputMode="numeric" autoComplete="one-time-code" maxLength={32} required /></label>
        <button className="control-action-button" type="submit" disabled={pending}>{pending ? "جارٍ التحقق…" : "رفع مؤقت"}</button>
      </div>
      <ActionFeedback state={state} />
    </form>
  );
}
