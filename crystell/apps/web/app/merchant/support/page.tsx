import Link from "next/link";

import { MerchantShell } from "@/components/merchant/merchant-shell";
import { SupportTicketForm } from "@/components/merchant/support-ticket-form";
import { loadMerchantContext } from "@/lib/server/merchant-context";
import { merchantApi } from "@/lib/server/session-api";
import type { SupportTicket } from "@/lib/support-types";

type PageProps = { searchParams: Promise<{ tenant?: string; store?: string; status?: string }> };
type TicketDirectory = { support_tickets: SupportTicket[] };

export default async function MerchantSupportPage({ searchParams }: PageProps) {
  const query = await searchParams;
  const context = await loadMerchantContext(query);
  const { tenants, selectedTenant, stores, selectedStore, role } = context;

  if (!selectedTenant) return <SupportEmptyState message="لا توجد شركة متاحة لهذا الحساب." />;

  const status = new Set(["open", "pending", "resolved", "closed"]).has(query.status ?? "") ? query.status : undefined;
  const result = selectedStore
    ? await merchantApi<TicketDirectory>(
        `/v1/stores/${encodeURIComponent(selectedStore.id)}/support/tickets${status ? `?status=${status}` : ""}`,
        selectedTenant.id,
      )
    : null;
  const tickets = result?.ok ? result.data?.support_tickets ?? [] : [];
  const contextQuery = selectedStore ? `tenant=${encodeURIComponent(selectedTenant.id)}&store=${encodeURIComponent(selectedStore.id)}` : "";

  return (
    <MerchantShell
      active="support"
      tenants={tenants}
      selectedTenant={selectedTenant}
      stores={stores}
      selectedStore={selectedStore}
      role={role}
      title="الدعم والمحادثات"
      description="تواصل مع فريق Crystell وتابع كل طلب في محادثة واحدة."
    >
      {!selectedStore ? <SupportEmptyState message="اختر متجرًا لفتح مركز الدعم." /> : (
        <section className="support-layout">
          <div className="support-column">
            <section className="panel">
              <div className="panel-heading"><div><span className="section-kicker">New conversation</span><h2>فتح تذكرة جديدة</h2></div></div>
              <SupportTicketForm tenantId={selectedTenant.id} storeId={selectedStore.id} />
            </section>
          </div>

          <section className="panel support-ticket-list">
            <div className="panel-heading">
              <div><span className="section-kicker">Support inbox</span><h2>تذاكر المتجر</h2></div>
              <span className="counter-badge">{tickets.length}</span>
            </div>
            <div className="support-filters">
              {["all", "open", "pending", "resolved", "closed"].map((value) => (
                <Link
                  className={(status ?? "all") === value ? "context-chip selected" : "context-chip"}
                  href={`/merchant/support?${contextQuery}${value === "all" ? "" : `&status=${value}`}`}
                  key={value}
                >
                  {statusLabel(value)}
                </Link>
              ))}
            </div>
            {result?.status === 403 ? <p className="panel-muted">حسابك لا يملك صلاحية قراءة تذاكر الدعم.</p> : tickets.length ? (
              <div className="ticket-stack">
                {tickets.map((ticket) => (
                  <Link className="ticket-card" href={`/merchant/support/${encodeURIComponent(ticket.id)}?${contextQuery}`} key={ticket.id}>
                    <div><span className="ticket-number">{ticket.ticket_number}</span><h3>{ticket.subject}</h3></div>
                    <div className="ticket-card-meta"><span className={`state-badge state-${ticket.status}`}>{statusLabel(ticket.status)}</span><span>{formatDateTime(ticket.last_message_at)}</span></div>
                  </Link>
                ))}
              </div>
            ) : <p className="panel-muted">لا توجد تذاكر في هذا القسم.</p>}
          </section>
        </section>
      )}
    </MerchantShell>
  );
}

function SupportEmptyState({ message }: { message: string }) {
  return <section className="empty-panel"><strong>{message}</strong><p>ستظهر المحادثات هنا بمجرد توفر سياق متجر صالح.</p></section>;
}

function statusLabel(status: string) {
  return ({ all: "الكل", open: "مفتوحة", pending: "بانتظارك", resolved: "محلولة", closed: "مغلقة" } as Record<string, string>)[status] ?? status;
}

function formatDateTime(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat("ar-EG", { dateStyle: "short", timeStyle: "short" }).format(date);
}
