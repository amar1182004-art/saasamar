"use client";

import { useActionState } from "react";

import {
  createSupportTicket,
  initialMerchantSupportState,
} from "@/app/merchant/support/actions";

export function SupportTicketForm({ tenantId, storeId }: { tenantId: string; storeId: string }) {
  const [state, action, pending] = useActionState(createSupportTicket, initialMerchantSupportState);

  return (
    <form action={action} className="support-compose">
      <input type="hidden" name="tenant_id" value={tenantId} />
      <input type="hidden" name="store_id" value={storeId} />
      <div className="form-grid two">
        <label><span>عنوان المشكلة</span><input name="subject" required minLength={3} maxLength={160} placeholder="مثال: إعداد شركة الشحن" /></label>
        <label><span>الأولوية</span><select name="priority" defaultValue="normal"><option value="low">منخفضة</option><option value="normal">عادية</option><option value="high">مرتفعة</option><option value="urgent">عاجلة</option></select></label>
      </div>
      <label><span>التفاصيل</span><textarea name="body" required maxLength={5_000} rows={5} placeholder="اشرح ما حدث والخطوات التي جربتها…" /></label>
      <div className="compose-actions">
        <button className="primary-button" type="submit" disabled={pending}>{pending ? "جارٍ الفتح…" : "فتح تذكرة"}</button>
        {state.status !== "idle" ? <p className={`form-feedback ${state.status}`}>{state.message}</p> : null}
      </div>
    </form>
  );
}
