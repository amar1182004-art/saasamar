"use client";

import { useState } from "react";

export function SupportAttachmentButton({ tenantId, storeId, ticketId, attachmentId, filename }: { tenantId: string; storeId: string; ticketId: string; attachmentId: string; filename: string }) {
  const [loading, setLoading] = useState(false);

  async function openAttachment() {
    setLoading(true);
    try {
      const response = await fetch("/api/merchant/support/attachments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "preview", tenantId, storeId, ticketId, attachmentId }),
      });
      const result = await response.json() as { preview_url?: string };
      if (response.ok && result.preview_url) window.open(result.preview_url, "_blank", "noopener,noreferrer");
    } finally {
      setLoading(false);
    }
  }

  return <button className="attachment-button" type="button" onClick={openAttachment} disabled={loading}>{loading ? "جارٍ الفتح…" : filename}</button>;
}
