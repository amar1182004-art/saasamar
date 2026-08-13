"use client";

import { useActionState } from "react";

import { saveFeatureFlag, type ControlActionState } from "@/app/control/actions";
import { ActionFeedback } from "@/components/control/action-feedback";

type FlagInput = {
  key: string;
  description: string | null;
  enabled: boolean;
  rollout_percentage: number;
  config: Record<string, unknown>;
} | null;

const initialState: ControlActionState = { status: "idle", message: "" };

export function FeatureFlagEditor({ flag }: { flag: FlagInput }) {
  const [state, action, pending] = useActionState(saveFeatureFlag, initialState);

  return (
    <form action={action} className="control-form panel">
      <div className="panel-heading"><div><span className="section-kicker">Release control</span><h2>{flag ? `تعديل ${flag.key}` : "Feature Flag جديد"}</h2></div></div>
      <div className="form-grid two">
        <label>المفتاح<input name="key" defaultValue={flag?.key ?? ""} pattern="[a-z0-9][a-z0-9._-]{0,119}" readOnly={Boolean(flag)} placeholder="new-checkout" required /></label>
        <label>نسبة الإطلاق<input name="rollout_percentage" type="number" min={0} max={100} step={1} defaultValue={flag?.rollout_percentage ?? 0} required /></label>
      </div>
      <label>الوصف<input name="description" maxLength={1000} defaultValue={flag?.description ?? ""} /></label>
      <label className="check-row"><input name="enabled" type="checkbox" defaultChecked={flag?.enabled ?? false} /><span>العلم مفعّل</span></label>
      <label>الإعدادات بصيغة JSON<textarea name="config" rows={8} defaultValue={JSON.stringify(flag?.config ?? {}, null, 2)} required /></label>
      <label>سبب التغيير<input name="reason" maxLength={500} placeholder="سبب واضح يظهر في Audit Log" required /></label>
      <div className="form-actions"><button className="control-action-button warning" disabled={pending} type="submit">{pending ? "جارٍ التحديث…" : "تطبيق التغيير الحي"}</button></div>
      <ActionFeedback state={state} />
    </form>
  );
}
