import Link from "next/link";

import { ControlShell } from "@/components/control/control-shell";
import { requireControlSession } from "@/lib/server/control-session";
import { controlApi } from "@/lib/server/session-api";

type AuditResponse = {
  audit_events: Array<{
    id: string; action: string;
    actor: { id: string; email: string; role: string } | null;
    target: { type: string | null; id: string | null };
    request_id: string | null; ip_fingerprint: string | null; reason: string | null;
    metadata: Record<string, unknown>; occurred_at: string;
  }>;
  pagination: { has_more: boolean; next_offset: number | null };
};

type PageProps = { searchParams: Promise<{ action?: string; actor_id?: string; target_type?: string; offset?: string }> };

export default async function AuditPage({ searchParams }: PageProps) {
  const me = await requireControlSession();
  const query = await searchParams;
  const filters = {
    action: clean(query.action, 160), actor_id: clean(query.actor_id, 40),
    target_type: clean(query.target_type, 160), offset: /^\d+$/.test(query.offset ?? "") ? query.offset! : "0",
  };
  const params = new URLSearchParams({ limit: "50", offset: filters.offset });
  if (filters.action) params.set("action", filters.action);
  if (filters.actor_id) params.set("actor_id", filters.actor_id);
  if (filters.target_type) params.set("target_type", filters.target_type);
  const result = await controlApi<AuditResponse>(`/control/v1/audit-events?${params}`);
  const events = result?.ok ? result.data?.audit_events ?? [] : [];
  const pagination = result?.data?.pagination;

  return <ControlShell active="audit" me={me} title="سجل التدقيق" description="سجل إداري غير قابل للتعديل، مع إخفاء تلقائي لأي مفاتيح أو بيانات حساسة.">
    <form className="filter-bar multi-filter" method="get">
      <label><span>Action</span><input name="action" defaultValue={filters.action} placeholder="control_plane.content_published" /></label>
      <label><span>Target type</span><input name="target_type" defaultValue={filters.target_type} placeholder="ControlPlaneContentDocument" /></label>
      <label><span>Actor ID</span><input name="actor_id" defaultValue={filters.actor_id} placeholder="UUID" /></label>
      <button className="control-action-button" type="submit">تصفية</button>
      <Link className="secondary-link" href="/control/audit">مسح</Link>
    </form>
    <section className="panel table-panel"><div className="panel-heading"><div><span className="section-kicker">Immutable history</span><h2>الأحداث الإدارية</h2></div><span className="counter-badge">{events.length}</span></div>
      {events.length ? <div className="audit-detail-list">{events.map((event) => <details className="audit-detail" key={event.id}><summary><span className="audit-mark" /><span><strong>{event.action}</strong><small>{event.actor?.email ?? "system"} · {formatDateTime(event.occurred_at)}</small></span><span className="state-badge">{event.actor?.role ?? "system"}</span></summary><div className="audit-metadata"><dl className="detail-list"><div><dt>Target</dt><dd>{event.target.type ?? "—"} · {event.target.id ?? "—"}</dd></div><div><dt>Request</dt><dd className="mono-value">{event.request_id ?? "—"}</dd></div><div><dt>IP fingerprint</dt><dd className="mono-value">{event.ip_fingerprint ?? "—"}</dd></div><div><dt>Reason</dt><dd>{event.reason ?? "—"}</dd></div></dl><pre>{JSON.stringify(event.metadata, null, 2)}</pre></div></details>)}</div> : <p className="panel-muted">لا توجد أحداث مطابقة أو لا يملك دورك صلاحية القراءة.</p>}
    </section>
    <div className="pagination-row">{Number(filters.offset) > 0 ? <Link className="secondary-link" href={pageHref(filters, Math.max(0, Number(filters.offset) - 50))}>السابق</Link> : <span />}{pagination?.has_more && pagination.next_offset !== null ? <Link className="secondary-link" href={pageHref(filters, pagination.next_offset)}>التالي</Link> : null}</div>
  </ControlShell>;
}

function clean(value: string | undefined, max: number) { return value?.trim().slice(0, max) ?? ""; }
function pageHref(filters: { action: string; actor_id: string; target_type: string }, offset: number) { const params = new URLSearchParams({ offset: String(offset) }); if (filters.action) params.set("action", filters.action); if (filters.actor_id) params.set("actor_id", filters.actor_id); if (filters.target_type) params.set("target_type", filters.target_type); return `/control/audit?${params}`; }
function formatDateTime(value: string) { const date = new Date(value); return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat("ar-EG", { dateStyle: "short", timeStyle: "short" }).format(date); }
