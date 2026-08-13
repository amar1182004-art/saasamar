import Link from "next/link";
import { redirect } from "next/navigation";

import { LogoutButton } from "@/components/auth/logout-button";
import { controlApi } from "@/lib/server/session-api";

type ControlMe = {
  user: { id: string; email: string; role: string };
  session: { id: string; expires_at: string; elevated: boolean; privilege_elevated_until: string | null };
};

type SecurityResponse = {
  security: {
    users: { total: number; active: number; suspended: number; locked: number; roles: Record<string, number> };
    sessions: { active: number; elevated: number };
    activity_24h: { audit_events: number; authentication_failures: number; privilege_elevations: number };
    generated_at: string;
  };
};

type TenantResponse = {
  tenants: Array<{
    id: string;
    name: string;
    slug: string;
    status: string;
    stores_count: number;
    active_stores_count: number;
    created_at: string;
  }>;
};

type AuditResponse = {
  audit_events: Array<{
    id: string;
    action: string;
    actor: { id: string; email: string; role: string } | null;
    target: { type: string | null; id: string | null };
    occurred_at: string;
  }>;
};

type FeatureFlagResponse = {
  feature_flags: Array<{
    id: string;
    key: string;
    description: string | null;
    enabled: boolean;
    rollout_percentage: number;
    updated_at: string;
  }>;
};

type ContentResponse = {
  content_documents: Array<{
    id: string;
    key: string;
    kind: string;
    locale: string;
    draft_version: number;
    published_version: number;
    published_at: string | null;
  }>;
};

export default async function ControlPage() {
  const meResult = await controlApi<ControlMe>("/control/v1/me");
  if (!meResult || meResult.status === 401) redirect("/control/login");
  if (!meResult.ok || !meResult.data) redirect("/control/login");

  const [securityResult, tenantsResult, auditResult, flagsResult, contentResult] = await Promise.all([
    controlApi<SecurityResponse>("/control/v1/security"),
    controlApi<TenantResponse>("/control/v1/tenants?limit=12"),
    controlApi<AuditResponse>("/control/v1/audit-events?limit=8"),
    controlApi<FeatureFlagResponse>("/control/v1/feature-flags"),
    controlApi<ContentResponse>("/control/v1/content"),
  ]);

  const me = meResult.data;
  const security = securityResult?.ok ? securityResult.data?.security : null;
  const tenants = tenantsResult?.ok ? tenantsResult.data?.tenants ?? [] : [];
  const audit = auditResult?.ok ? auditResult.data?.audit_events ?? [] : [];
  const flags = flagsResult?.ok ? flagsResult.data?.feature_flags ?? [] : [];
  const content = contentResult?.ok ? contentResult.data?.content_documents ?? [] : [];

  return (
    <main className="admin-layout control-layout">
      <aside className="admin-sidebar control-sidebar">
        <div>
          <Link className="sidebar-brand" href="/">Crystell</Link>
          <span className="sidebar-caption">Super Admin</span>
        </div>
        <nav className="sidebar-nav" aria-label="Control plane navigation">
          <Link className="nav-item active" href="/control">Overview</Link>
          <span className="nav-item muted-nav">Merchants</span>
          <span className="nav-item muted-nav">Stores</span>
          <span className="nav-item muted-nav">Plans</span>
          <span className="nav-item muted-nav">Integrations</span>
          <span className="nav-item muted-nav">Content</span>
          <span className="nav-item muted-nav">Feature Flags</span>
          <span className="nav-item muted-nav">Security</span>
          <span className="nav-item muted-nav">Audit</span>
        </nav>
        <div className="sidebar-footer">
          <span className="role-pill control-role">{me.user.role}</span>
          <LogoutButton endpoint="/api/control/auth/logout" redirectTo="/control/login" />
        </div>
      </aside>

      <section className="admin-main">
        <header className="admin-topbar">
          <div>
            <span className="section-kicker">Control plane</span>
            <h1>Platform overview</h1>
            <p className="topbar-subtitle">{me.user.email}</p>
          </div>
          <div className={me.session.elevated ? "topbar-status elevated" : "topbar-status"}>
            <span className="status-dot" />
            {me.session.elevated ? "Privilege elevated" : "Standard privilege"}
          </div>
        </header>

        {security ? (
          <section className="metric-grid control-metrics">
            <Metric label="Control users" value={security.users.total} meta={`${security.users.active} active`} />
            <Metric label="Active sessions" value={security.sessions.active} meta={`${security.sessions.elevated} elevated`} />
            <Metric label="Audit events · 24h" value={security.activity_24h.audit_events} meta={`${security.activity_24h.privilege_elevations} elevations`} />
            <Metric label="Auth failures · 24h" value={security.activity_24h.authentication_failures} meta={`${security.users.locked} locked users`} tone={security.activity_24h.authentication_failures > 0 ? "danger" : "normal"} />
          </section>
        ) : (
          <section className="permission-banner">
            <strong>Security Center metrics محجوبة لهذه الصلاحية.</strong>
            <span>يمكنك الاستمرار في استخدام الأقسام التي يسمح بها دور {me.user.role}.</span>
          </section>
        )}

        <section className="dashboard-grid two-column">
          <article className="panel table-panel">
            <div className="panel-heading">
              <div><span className="section-kicker">Tenant directory</span><h2>أحدث الشركات المتاحة</h2></div>
              <span className="counter-badge">{tenants.length}</span>
            </div>
            {tenants.length ? (
              <div className="table-scroll">
                <table className="data-table">
                  <thead><tr><th>الشركة</th><th>الحالة</th><th>المتاجر</th><th>النشطة</th></tr></thead>
                  <tbody>
                    {tenants.map((tenant) => (
                      <tr key={tenant.id}>
                        <td><strong>{tenant.name}</strong><small className="cell-subtitle">{tenant.slug}</small></td>
                        <td><span className={`state-badge state-${tenant.status}`}>{tenant.status}</span></td>
                        <td>{tenant.stores_count}</td>
                        <td>{tenant.active_stores_count}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : <p className="panel-muted">لا توجد شركات ظاهرة لهذه الجلسة.</p>}
          </article>

          <article className="panel">
            <div className="panel-heading">
              <div><span className="section-kicker">Feature flags</span><h2>حالة الإطلاقات</h2></div>
              <span className="counter-badge">{flags.length}</span>
            </div>
            {flags.length ? (
              <div className="flag-list">
                {flags.slice(0, 8).map((flag) => (
                  <div className="flag-row" key={flag.id}>
                    <div><strong>{flag.key}</strong><small>{flag.description ?? "بدون وصف"}</small></div>
                    <span className={flag.enabled ? "state-badge state-active" : "state-badge"}>{flag.enabled ? `${flag.rollout_percentage}%` : "off"}</span>
                  </div>
                ))}
              </div>
            ) : <p className="panel-muted">لم يتم إنشاء Feature Flags بعد.</p>}
          </article>
        </section>

        <section className="dashboard-grid two-column">
          <article className="panel">
            <div className="panel-heading">
              <div><span className="section-kicker">Platform content</span><h2>CMS & Branding</h2></div>
              <span className="counter-badge">{content.length}</span>
            </div>
            {content.length ? (
              <div className="flag-list">
                {content.slice(0, 8).map((document) => (
                  <div className="flag-row" key={document.id}>
                    <div><strong>{document.key}</strong><small>{document.kind} · {document.locale}</small></div>
                    <span className={document.draft_version === document.published_version ? "state-badge state-active" : "state-badge state-warning"}>
                      v{document.published_version}/{document.draft_version}
                    </span>
                  </div>
                ))}
              </div>
            ) : <p className="panel-muted">لا توجد مستندات CMS حتى الآن.</p>}
          </article>

          <article className="panel">
            <div className="panel-heading">
              <div><span className="section-kicker">Audit trail</span><h2>آخر الأحداث الإدارية</h2></div>
            </div>
            {audit.length ? (
              <div className="audit-list">
                {audit.map((event) => (
                  <div className="audit-row" key={event.id}>
                    <span className="audit-mark" />
                    <div><strong>{event.action}</strong><small>{event.actor?.email ?? "system"} · {formatDateTime(event.occurred_at)}</small></div>
                  </div>
                ))}
              </div>
            ) : <p className="panel-muted">لا توجد أحداث Audit متاحة.</p>}
          </article>
        </section>
      </section>
    </main>
  );
}

function Metric({ label, value, meta, tone = "normal" }: { label: string; value: number; meta: string; tone?: "normal" | "danger" }) {
  return <article className={`metric-card ${tone === "danger" ? "metric-danger" : ""}`}><span>{label}</span><strong>{value.toLocaleString("en-US")}</strong><small>{meta}</small></article>;
}

function formatDateTime(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? value
    : new Intl.DateTimeFormat("ar-EG", { dateStyle: "short", timeStyle: "short" }).format(date);
}
