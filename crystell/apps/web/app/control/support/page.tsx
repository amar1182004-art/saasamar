import Link from "next/link";

import { ControlShell } from "@/components/control/control-shell";
import { requireControlSession } from "@/lib/server/control-session";
import { controlApi } from "@/lib/server/session-api";

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
};

type PageProps = { searchParams: Promise<{ q?: string; status?: string }> };

export default async function ControlSupportPage({ searchParams }: PageProps) {
  const me = await requireControlSession();
  const query = await searchParams;
  const search = query.q?.trim().slice(0, 160) ?? "";
  const status = new Set(["open", "pending", "resolved", "closed"]).has(query.status ?? "") ? query.status : "";
  const params = new URLSearchParams({ limit: "100" });
  if (search) params.set("q", search);
  if (status) params.set("status", status);
  const result = await controlApi<{ support_tickets: ControlTicket[] }>(`/control/v1/support/tickets?${params}`);
  const tickets = result?.ok ? result.data?.support_tickets ?? [] : [];

  return (
    <ControlShell active="support" me={me} title="مركز الدعم" description="طابور مستقل لخدمة التجار دون فتح اتصال مباشر بقاعدة بيانات أي Tenant.">
      <form className="filter-bar multi-filter" method="get">
        <label><span>بحث بالتذكرة أو الشركة</span><input name="q" defaultValue={search} maxLength={160} placeholder="SUP-… أو اسم الشركة" /></label>
        <label><span>الحالة</span><select name="status" defaultValue={status}><option value="">كل الحالات</option><option value="open">مفتوحة</option><option value="pending">بانتظار التاجر</option><option value="resolved">محلولة</option><option value="closed">مغلقة</option></select></label>
        <button className="control-action-button" type="submit">تطبيق</button>
        {search || status ? <Link className="secondary-link" href="/control/support">مسح</Link> : null}
      </form>

      <section className="panel table-panel">
        <div className="panel-heading"><div><span className="section-kicker">Support queue</span><h2>تذاكر التجار</h2></div><span className="counter-badge">{tickets.length}</span></div>
        {result?.status === 403 ? <p className="panel-muted">دورك الحالي لا يملك صلاحية قراءة مركز الدعم.</p> : tickets.length ? (
          <div className="table-scroll"><table className="data-table">
            <thead><tr><th>التذكرة</th><th>الشركة / المتجر</th><th>العنوان</th><th>الأولوية</th><th>الحالة</th><th>آخر تحديث</th><th /></tr></thead>
            <tbody>{tickets.map((ticket) => <tr key={ticket.id}>
              <td className="strong-cell">{ticket.ticket_number}</td>
              <td><strong>{ticket.tenant.name}</strong><small className="cell-subtitle">{ticket.store.name}</small></td>
              <td>{ticket.subject}</td><td>{priorityLabel(ticket.priority)}</td>
              <td><span className={`state-badge state-${ticket.status}`}>{statusLabel(ticket.status)}</span></td>
              <td>{formatDateTime(ticket.last_message_at)}</td>
              <td><Link className="table-link" href={`/control/support/${encodeURIComponent(ticket.id)}`}>فتح</Link></td>
            </tr>)}</tbody>
          </table></div>
        ) : <p className="panel-muted">لا توجد تذاكر مطابقة.</p>}
      </section>
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
  return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat("ar-EG", { dateStyle: "short", timeStyle: "short" }).format(date);
}
