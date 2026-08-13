"use client";

import { useActionState, useEffect, useRef, useState } from "react";

import {
  initialMerchantSupportState,
  replySupportTicket,
} from "@/app/merchant/support/actions";

type UploadedAttachment = { id: string; filename: string };

export function SupportReplyForm({ tenantId, storeId, ticketId, closed }: { tenantId: string; storeId: string; ticketId: string; closed: boolean }) {
  const [state, action, pending] = useActionState(replySupportTicket, initialMerchantSupportState);
  const [attachments, setAttachments] = useState<UploadedAttachment[]>([]);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState("");
  const fileInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (state.status === "success") {
      setAttachments([]);
      if (fileInput.current) fileInput.current.value = "";
    }
  }, [state.status]);

  async function uploadSelectedFile() {
    const file = fileInput.current?.files?.[0];
    if (!file) return setUploadError("اختر ملفًا أولًا.");
    if (attachments.length >= 10) return setUploadError("الحد الأقصى 10 مرفقات في الرسالة.");

    setUploading(true);
    setUploadError("");
    try {
      const issue = await fetch("/api/merchant/support/attachments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "issue", tenantId, storeId, ticketId, filename: file.name, contentType: file.type, byteSize: file.size }),
      });
      const issued = await issue.json() as { upload?: { attachment_id: string; upload_url: string }; message?: string };
      if (!issue.ok || !issued.upload) throw new Error(issued.message ?? "تعذر تجهيز رابط الرفع.");

      const stored = await fetch(issued.upload.upload_url, { method: "PUT", headers: { "Content-Type": file.type }, body: file });
      if (!stored.ok) throw new Error("تعذر رفع الملف إلى التخزين الآمن.");

      const complete = await fetch("/api/merchant/support/attachments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "complete", tenantId, storeId, ticketId, attachmentId: issued.upload.attachment_id }),
      });
      const completed = await complete.json() as { attachment?: { id: string; filename: string }; message?: string };
      if (!complete.ok || !completed.attachment) throw new Error(completed.message ?? "تعذر تأكيد الملف.");

      setAttachments((current) => [...current, completed.attachment!]);
      if (fileInput.current) fileInput.current.value = "";
    } catch (error) {
      setUploadError(error instanceof Error ? error.message : "تعذر رفع الملف.");
    } finally {
      setUploading(false);
    }
  }

  if (closed) return <p className="permission-banner">هذه التذكرة مغلقة ولا تستقبل ردودًا جديدة.</p>;

  return (
    <form action={action} className="support-compose">
      <input type="hidden" name="tenant_id" value={tenantId} />
      <input type="hidden" name="store_id" value={storeId} />
      <input type="hidden" name="ticket_id" value={ticketId} />
      {attachments.map((attachment) => <input type="hidden" name="attachment_id" value={attachment.id} key={attachment.id} />)}
      <label><span>رسالتك</span><textarea name="body" required maxLength={5_000} rows={4} placeholder="اكتب ردك لفريق الدعم…" /></label>
      <div className="attachment-uploader">
        <input ref={fileInput} type="file" accept="image/jpeg,image/png,image/webp,image/avif,image/gif,video/mp4,video/webm,video/quicktime,application/pdf,text/plain,text/csv,application/zip" />
        <button className="ghost-button" type="button" onClick={uploadSelectedFile} disabled={uploading}>{uploading ? "جارٍ الرفع…" : "رفع المرفق"}</button>
      </div>
      {attachments.length ? <div className="attachment-chips">{attachments.map((attachment) => <span key={attachment.id}>{attachment.filename}</span>)}</div> : null}
      {uploadError ? <p className="form-feedback error" role="alert">{uploadError}</p> : null}
      <div className="compose-actions">
        <button className="primary-button" type="submit" disabled={pending || uploading}>{pending ? "جارٍ الإرسال…" : "إرسال الرد"}</button>
        {state.status !== "idle" ? <p className={`form-feedback ${state.status}`}>{state.message}</p> : null}
      </div>
    </form>
  );
}
