import { ControlShell } from "@/components/control/control-shell";
import { requireControlSession } from "@/lib/server/control-session";
import { controlApi } from "@/lib/server/session-api";

type SecurityResponse = { security: { users: { total: number; active: number; suspended: number; locked: number; roles: Record<string, number> }; sessions: { active: number; elevated: number }; activity_24h: { audit_events: number; authentication_failures: number; privilege_elevations: number }; generated_at: string } };

export default async function SecurityPage() {
  const me = await requireControlSession();
  const result = await controlApi<SecurityResponse>("/control/v1/security");
  const security = result?.ok ? result.data?.security : null;
  return <ControlShell active="security" me={me} title="مركز الأمان" description="مؤشرات حسابات الإدارة والجلسات والنشاط الأمني خلال آخر 24 ساعة.">
    {security ? <>
      <section className="metric-grid"><Metric label="حسابات الإدارة" value={security.users.total} meta={`${security.users.active} نشط`} /><Metric label="الجلسات النشطة" value={security.sessions.active} meta={`${security.sessions.elevated} مرتفعة`} /><Metric label="محاولات فاشلة" value={security.activity_24h.authentication_failures} meta="آخر 24 ساعة" danger={security.activity_24h.authentication_failures > 0} /><Metric label="حسابات مقفولة" value={security.users.locked} meta={`${security.users.suspended} موقوف`} danger={security.users.locked > 0} /></section>
      <section className="dashboard-grid two-column"><article className="panel"><div className="panel-heading"><div><span className="section-kicker">Role distribution</span><h2>توزيع الأدوار</h2></div></div><div className="compact-stats">{Object.entries(security.users.roles).map(([role, count]) => <span key={role}><strong>{count}</strong>{role}</span>)}</div></article><article className="panel"><div className="panel-heading"><div><span className="section-kicker">Activity · 24h</span><h2>النشاط الإداري</h2></div></div><dl className="detail-list"><div><dt>أحداث Audit</dt><dd>{security.activity_24h.audit_events}</dd></div><div><dt>رفع الصلاحيات</dt><dd>{security.activity_24h.privilege_elevations}</dd></div><div><dt>آخر تحديث</dt><dd>{formatDateTime(security.generated_at)}</dd></div></dl></article></section>
    </> : <section className="permission-banner"><strong>بيانات مركز الأمان محجوبة.</strong><span>هذه الصفحة تتطلب دور admin أو owner وصلاحية security.read.</span></section>}
  </ControlShell>;
}

function Metric({ label, value, meta, danger = false }: { label: string; value: number; meta: string; danger?: boolean }) { return <article className={`metric-card ${danger ? "metric-danger" : ""}`}><span>{label}</span><strong>{value.toLocaleString("ar-EG")}</strong><small>{meta}</small></article>; }
function formatDateTime(value: string) { const date = new Date(value); return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat("ar-EG", { dateStyle: "medium", timeStyle: "short" }).format(date); }
