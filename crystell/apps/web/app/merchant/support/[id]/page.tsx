import Link from "next/link";

import { MerchantShell } from "@/components/merchant/merchant-shell";
import { SupportAttachmentButton } from "@/components/merchant/support-attachment-button";
import { SupportReplyForm } from "@/components/merchant/support-reply-form";
import { loadMerchantContext } from "@/lib/server/merchant-context";
import { merchantApi } from "@/lib/server/session-api";
import type { SupportTicket } from "@/lib/support-types";

type PageProps = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ tenant?: string; store?: string }>;
};

export default async function MerchantSupportThreadPage({ params, searchParams }: PageProps) {
  const [{ id }, query] = await Promise.all([params, searchParams]);
  const context = await loadMerchantContext(query);
  const { tenants, selectedTenant, stores, selectedStore, role } = context;
  if (!selectedTenant || !selectedStore) return <main className="standalone-state"><section className="empty-panel"><strong>لا يوجد متجر صالح لعرض المحادثة.</strong></section></main>;

  const result = await merchantApi<{ support_ticket: SupportTicket }>(
    `/v1/stores/${encodeURIComponent(selectedStore.id)}/support/tickets/${encodeURIComponent(id)}`,
    selectedTenant.id,
  );
  const ticket = result?.ok ? result.data?.support_ticket : null;
  const contextQuery = `tenant=${encodeURIComponent(selectedTenant.id)}&store=${encodeURIComponent(selectedStore.id)}`;

  return (
    <MerchantShell active="support" tenants={tenants} selectedTenant={selectedTenant} stores={stores} selectedStore={selectedStore} role={role} title={ticket?.ticket_number ?? "تذكرة الدعم"} description={ticket?.subject ?? "المحادثة غير متاحة أو لا تملك صلاحية قراءتها."}>
      <Link className="secondary-link support-back" href={`/merchant/support?${contextQuery}`}>العودة إلى كل التذاكر</Link>
      {!ticket ? <section className="empty-panel error-panel"><strong>تعذر عرض هذه التذكرة.</strong><p>قد تكون غير موجودة أو تابعة لحساب آخر.</p></section> : (
        <section className="support-thread-layout">
          <article className="panel conversation-panel">
            <div className="ticket-summary"><div><span className={`state-badge state-${ticket.status}`}>{statusLabel(ticket.status)}</span><span className="priority-label">أولوية {priorityLabel(ticket.priority)}</span></div><small>بدأت {formatDateTime(ticket.created_at)}</small></div>
            <div className="message-thread">
              {ticket.messages?.map((message) => (
                <article className={`message-bubble message-${message.author_type}`} key={message.id}>
                  <div className="message-author"><strong>{message.author_type === "merchant" ? "أنت" : message.author_type === "support" ? "فريق Crystell" : "النظام"}</strong><time>{formatDateTime(message.created_at)}</time></div>
                  <p>{message.body}</p>
                  {message.attachments?.length ? <div className="message-attachments">{message.attachments.map((attachment) => (
                    <SupportAttachmentButton tenantId={selectedTenant.id} storeId={selectedStore.id} ticketId={ticket.id} attachmentId={attachment.id} filename={attachment.filename} key={attachment.id} />
                  ))}</div> : null}
                </article>
              ))}
            </div>
          </article>
          <aside className="panel reply-panel">
            <div className="panel-heading"><div><span className="section-kicker">Reply</span><h2>إضافة رد</h2></div></div>
            <SupportReplyForm tenantId={selectedTenant.id} storeId={selectedStore.id} ticketId={ticket.id} closed={ticket.status === "closed"} />
          </aside>
        </section>
      )}
    </MerchantShell>
  );
}

function statusLabel(status: string) {
  return ({ open: "مفتوحة", pending: "بانتظارك", resolved: "محلولة", closed: "مغلقة" } as Record<string, string>)[status] ?? status;
}
function priorityLabel(priority: string) {
  return ({ low: "منخفضة", normal: "عادية", high: "مرتفعة", urgent: "عاجلة" } as Record<string, string>)[priority] ?? priority;
}
function formatDateTime(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat("ar-EG", { dateStyle: "medium", timeStyle: "short" }).format(date);
}
