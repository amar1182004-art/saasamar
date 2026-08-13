"use client";

import { useActionState } from "react";

import {
  initialControlSupportState,
  replyToSupportTicket,
  transitionSupportTicket,
} from "@/app/control/support/actions";

export function SupportConsole({ ticketId, currentStatus }: { ticketId: string; currentStatus: string }) {
  const [replyState, replyAction, replyPending] = useActionState(replyToSupportTicket, initialControlSupportState);
  const [statusState, statusAction, statusPending] = useActionState(transitionSupportTicket, initialControlSupportState);

  return (
    <div className="support-console-stack">
      <form action={replyAction} className="control-form support-compose">
        <input type="hidden" name="ticket_id" value={ticketId} />
        <label><span>رد فريق الدعم</span><textarea name="body" required maxLength={5_000} rows={5} placeholder="اكتب ردًا واضحًا للتاجر…" /></label>
        <label><span>سبب الإجراء · Audit</span><input name="reason" required minLength={3} maxLength={500} placeholder="مثال: Respond to merchant request" /></label>
        <button className="control-action-button" type="submit" disabled={replyPending}>{replyPending ? "جارٍ الإرسال…" : "إرسال الرد"}</button>
        {replyState.status !== "idle" ? <p className={`form-feedback ${replyState.status}`}>{replyState.message}</p> : null}
      </form>

      <form action={statusAction} className="control-form support-compose compact-support-form">
        <input type="hidden" name="ticket_id" value={ticketId} />
        <label><span>حالة التذكرة</span><select name="status" defaultValue={currentStatus}><option value="open">مفتوحة</option><option value="pending">بانتظار التاجر</option><option value="resolved">محلولة</option><option value="closed">مغلقة</option></select></label>
        <label><span>سبب التغيير · Audit</span><input name="reason" required minLength={3} maxLength={500} placeholder="سبب تغيير الحالة" /></label>
        <button className="control-action-button" type="submit" disabled={statusPending}>{statusPending ? "جارٍ الحفظ…" : "تحديث الحالة"}</button>
        {statusState.status !== "idle" ? <p className={`form-feedback ${statusState.status}`}>{statusState.message}</p> : null}
      </form>
    </div>
  );
}
