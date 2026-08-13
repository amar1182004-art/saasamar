import Link from "next/link";

import { ControlAttachmentButton } from "@/components/control/control-attachment-button";
import { ControlShell } from "@/components/control/control-shell";
import { SupportConsole } from "@/components/control/support-console";
import { requireControlSession } from "@/lib/server/control-session";
import { controlApi } from "@/lib/server/session-api";
import type { SupportAttachment, SupportMessage } from "@/lib/support-types";

type ControlTicket = {
  id: string;
  tenant: { id: string; name: string };
  store: { id: string; name: string };
  ticket_number: string;
  subject: string;
  priority: string;
  status: string;
  source: string;
  last_message_at: string;
  created_at: string;
  messages: Array<SupportMessage & { author_label: string; attachments: SupportAttachment[] }>;
};

export default async function ControlSupportThreadPage({ params }: { params: Promise<{ id: string }> }) {
  const me = await requireControlSession();
  const { id } = await params;
  const result = await controlApi<{ support_ticket: ControlTicket }>(`/control/v1/support/tickets/${encodeURIComponent(id)}`);
  const ticket = result?.ok ? result.data?.support_ticket : null;

  return (
    <ControlShell active="support" me={me} title={ticket?.ticket_number ?? "تذكرة الدعم"} description={ticket ? `${ticket.tenant.name} · ${ticket.store.name}` : "التذكرة غير موجودة أو غير متاحة لدورك."}>
      <Link className="secondary-link support-back" href="/control/support">العودة إلى طابور الدعم</Link>
      {!ticket ? <section className="empty-panel error-panel"><strong>تعذر عرض التذكرة.</strong><p>تحقق من الرابط أو من صلاحية support.read.</p></section> : (
        <section className="support-thread-layout control-support-thread">
          <article className="panel conversation-panel">
            <div className="ticket-summary"><div><span className={`state-badge state-${ticket.status}`}>{statusLabel(ticket.status)}</span><span className="priority-label">أولوية {priorityLabel(ticket.priority)}</span></div><small>{ticket.subject}</small></div>
            <div className="message-thread">
              {ticket.messages.map((message) => (
                <article className={`message-bubble message-${message.author_type}`} key={message.id}>
                  <div className="message-author"><strong>{message.author_label}</strong><time>{formatDateTime(message.created_at)}</time></div>
                  <p>{message.body}</p>
                  {message.attachments?.length ? <div className="message-attachments">{message.attachments.map((attachment) => (
                    <ControlAttachmentButton ticketId={ticket.id} attachmentId={attachment.id} filename={attachment.filename} key={attachment.id} />
                  ))}</div> : null}
                </article>
              ))}
            </div>
          </article>
          <aside className="panel reply-panel"><div className="panel-heading"><div><span className="section-kicker">Support actions</span><h2>الرد والإدارة</h2></div></div><SupportConsole ticketId={ticket.id} currentStatus={ticket.status} /></aside>
        </section>
      )}
    </ControlShell>
  );
}

function statusLabel(status: string) {
  return ({ open: "مفتوحة", pending: "بانتظار التاجر", resolved: "محلولة", closed: "مغلقة" } as Record<string, string>)[status] ?? status;
}
function priorityLabel(priority: string) {
  return ({ low: "منخفضة", normal: "عادية", high: "مرتفعة", urgent: "عاجلة" } as Record<string, string>)[priority] ?? priority;
}
function formatDateTime(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat("ar-EG", { dateStyle: "medium", timeStyle: "short" }).format(date);
}
