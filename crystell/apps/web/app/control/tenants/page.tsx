import Link from "next/link";

import { ControlShell } from "@/components/control/control-shell";
import { requireControlSession } from "@/lib/server/control-session";
import { controlApi } from "@/lib/server/session-api";

type TenantDirectory = {
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

type PageProps = { searchParams: Promise<{ q?: string }> };

export default async function TenantsPage({ searchParams }: PageProps) {
  const me = await requireControlSession();
  const query = (await searchParams).q?.trim().slice(0, 120) ?? "";
  const path = `/control/v1/tenants?limit=100${query ? `&q=${encodeURIComponent(query)}` : ""}`;
  const result = await controlApi<TenantDirectory>(path);
  const tenants = result?.ok ? result.data?.tenants ?? [] : [];

  return (
    <ControlShell active="tenants" me={me} title="الشركات والمتاجر" description="بحث آمن وملخص دعم لكل Tenant بدون دخول مباشر إلى بياناته.">
      <form className="filter-bar" method="get">
        <label><span>بحث بالاسم أو Slug</span><input name="q" defaultValue={query} maxLength={120} placeholder="مثال: crystell-store" /></label>
        <button className="control-action-button" type="submit">بحث</button>
        {query ? <Link className="secondary-link" href="/control/tenants">مسح البحث</Link> : null}
      </form>

      <section className="panel table-panel">
        <div className="panel-heading"><div><span className="section-kicker">Tenant directory</span><h2>الشركات المتاحة</h2></div><span className="counter-badge">{tenants.length}</span></div>
        {result?.status === 403 ? <p className="panel-muted">دورك الحالي لا يملك صلاحية قراءة الشركات.</p> : tenants.length ? (
          <div className="table-scroll"><table className="data-table">
            <thead><tr><th>الشركة</th><th>الحالة</th><th>المتاجر</th><th>النشطة</th><th>تاريخ الإنشاء</th><th /></tr></thead>
            <tbody>{tenants.map((tenant) => <tr key={tenant.id}>
              <td><strong>{tenant.name}</strong><small className="cell-subtitle">{tenant.slug}</small></td>
              <td><span className={`state-badge state-${tenant.status}`}>{tenant.status}</span></td>
              <td>{tenant.stores_count}</td><td>{tenant.active_stores_count}</td><td>{formatDate(tenant.created_at)}</td>
              <td><Link className="table-link" href={`/control/tenants/${encodeURIComponent(tenant.id)}`}>فتح الملخص</Link></td>
            </tr>)}</tbody>
          </table></div>
        ) : <p className="panel-muted">لا توجد نتائج مطابقة.</p>}
      </section>
    </ControlShell>
  );
}

function formatDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat("ar-EG", { dateStyle: "medium" }).format(date);
}
