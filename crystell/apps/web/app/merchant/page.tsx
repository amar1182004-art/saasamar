import Link from "next/link";
import { redirect } from "next/navigation";

import { LogoutButton } from "@/components/auth/logout-button";
import { merchantApi } from "@/lib/server/session-api";

type TenantDirectory = {
  tenants: Array<{
    id: string;
    name: string;
    slug: string;
    status: string;
    membership: { role: string; status: string };
    stores_count: number;
    accessible: boolean;
  }>;
};

type StoreDirectory = {
  tenant_id: string;
  role: string;
  stores: Array<{ id: string; name: string; slug: string; status: string }>;
};

type DashboardResponse = {
  dashboard: {
    store: { id: string; name: string; status: string };
    orders: {
      total: number;
      pending: number;
      confirmed: number;
      unpaid: number;
      paid: number;
      paid_order_value_by_currency: Record<string, number>;
    };
    products: { total: number; active: number; draft: number; archived: number };
    inventory: { out_of_stock_levels: number; reserved_units: number; on_hand_units: number };
    shipments: { total: number; label_ready: number; in_transit: number; delivered: number; failed: number };
    recent_orders: Array<{
      id: string;
      order_number: string;
      status: string;
      payment_status: string;
      fulfillment_status: string;
      total_cents: number;
      currency: string;
      created_at: string;
    }>;
  };
};

type MerchantPageProps = {
  searchParams: Promise<{ tenant?: string; store?: string }>;
};

export default async function MerchantPage({ searchParams }: MerchantPageProps) {
  const query = await searchParams;
  const tenantResult = await merchantApi<TenantDirectory>("/v1/tenants");

  if (!tenantResult || tenantResult.status === 401) redirect("/merchant/login");

  const tenants = tenantResult.data?.tenants.filter((tenant) => tenant.accessible) ?? [];
  const selectedTenant = tenants.find((tenant) => tenant.id === query.tenant) ?? tenants[0];

  if (!selectedTenant) {
    return <MerchantEmptyState />;
  }

  const storesResult = await merchantApi<StoreDirectory>("/v1/stores", selectedTenant.id);
  if (!storesResult || storesResult.status === 401) redirect("/merchant/login");

  const stores = storesResult.data?.stores ?? [];
  const selectedStore = stores.find((store) => store.id === query.store) ?? stores[0];

  const dashboardResult = selectedStore
    ? await merchantApi<DashboardResponse>(`/v1/stores/${encodeURIComponent(selectedStore.id)}/dashboard`, selectedTenant.id)
    : null;
  const dashboard = dashboardResult?.ok ? dashboardResult.data?.dashboard : null;

  return (
    <main className="admin-layout">
      <aside className="admin-sidebar merchant-sidebar">
        <div>
          <Link className="sidebar-brand" href="/">Crystell</Link>
          <span className="sidebar-caption">Merchant Admin</span>
        </div>
        <nav className="sidebar-nav" aria-label="Merchant navigation">
          <Link className="nav-item active" href="/merchant">الرئيسية</Link>
          <span className="nav-item muted-nav">المنتجات</span>
          <span className="nav-item muted-nav">الطلبات</span>
          <span className="nav-item muted-nav">المخزون</span>
          <span className="nav-item muted-nav">الشحن</span>
          <span className="nav-item muted-nav">التصميم</span>
          <span className="nav-item muted-nav">الفوترة</span>
          <span className="nav-item muted-nav">الأمان</span>
        </nav>
        <div className="sidebar-footer">
          <span className="role-pill">{storesResult.data?.role ?? selectedTenant.membership.role}</span>
          <LogoutButton endpoint="/api/merchant/auth/logout" redirectTo="/merchant/login" />
        </div>
      </aside>

      <section className="admin-main">
        <header className="admin-topbar">
          <div>
            <span className="section-kicker">Merchant dashboard</span>
            <h1>{selectedStore?.name ?? selectedTenant.name}</h1>
          </div>
          <div className="topbar-status"><span className="status-dot" /> الجلسة آمنة</div>
        </header>

        <div className="context-strip">
          <div>
            <span className="context-label">الشركة</span>
            <div className="context-links">
              {tenants.map((tenant) => (
                <Link
                  className={tenant.id === selectedTenant.id ? "context-chip selected" : "context-chip"}
                  href={`/merchant?tenant=${encodeURIComponent(tenant.id)}`}
                  key={tenant.id}
                >
                  {tenant.name}
                </Link>
              ))}
            </div>
          </div>
          {stores.length > 0 ? (
            <div>
              <span className="context-label">المتجر</span>
              <div className="context-links">
                {stores.map((store) => (
                  <Link
                    className={store.id === selectedStore?.id ? "context-chip selected" : "context-chip"}
                    href={`/merchant?tenant=${encodeURIComponent(selectedTenant.id)}&store=${encodeURIComponent(store.id)}`}
                    key={store.id}
                  >
                    {store.name}
                  </Link>
                ))}
              </div>
            </div>
          ) : null}
        </div>

        {!selectedStore ? (
          <section className="empty-panel">
            <strong>لا يوجد متجر داخل هذه الشركة حتى الآن.</strong>
            <p>عند إنشاء أول متجر سيظهر ملخص التشغيل هنا تلقائيًا.</p>
          </section>
        ) : !dashboard ? (
          <section className="empty-panel error-panel">
            <strong>تعذر تحميل ملخص المتجر.</strong>
            <p>الجلسة ما زالت فعالة، لكن API لم تُرجع بيانات Dashboard صالحة.</p>
          </section>
        ) : (
          <MerchantDashboard dashboard={dashboard} />
        )}
      </section>
    </main>
  );
}

function MerchantDashboard({ dashboard }: { dashboard: DashboardResponse["dashboard"] }) {
  const revenue = Object.entries(dashboard.orders.paid_order_value_by_currency);

  return (
    <>
      <section className="metric-grid">
        <Metric label="إجمالي الطلبات" value={dashboard.orders.total} meta={`${dashboard.orders.pending} قيد الانتظار`} />
        <Metric label="الطلبات المدفوعة" value={dashboard.orders.paid} meta={`${dashboard.orders.unpaid} غير مدفوعة`} />
        <Metric label="المنتجات النشطة" value={dashboard.products.active} meta={`${dashboard.products.draft} مسودة`} />
        <Metric label="نفاد المخزون" value={dashboard.inventory.out_of_stock_levels} meta={`${dashboard.inventory.on_hand_units} وحدة متاحة`} tone={dashboard.inventory.out_of_stock_levels > 0 ? "danger" : "normal"} />
      </section>

      <section className="dashboard-grid two-column">
        <article className="panel">
          <div className="panel-heading">
            <div><span className="section-kicker">Revenue</span><h2>قيمة الطلبات المدفوعة</h2></div>
          </div>
          {revenue.length ? (
            <div className="revenue-list">
              {revenue.map(([currency, cents]) => (
                <div className="revenue-row" key={currency}>
                  <span>{currency}</span>
                  <strong>{formatMoney(cents, currency)}</strong>
                </div>
              ))}
            </div>
          ) : <p className="panel-muted">لا توجد طلبات مدفوعة بعد.</p>}
        </article>

        <article className="panel">
          <div className="panel-heading">
            <div><span className="section-kicker">Fulfillment</span><h2>حالة الشحن</h2></div>
          </div>
          <div className="compact-stats">
            <span><strong>{dashboard.shipments.label_ready}</strong> جاهز للشحن</span>
            <span><strong>{dashboard.shipments.in_transit}</strong> في الطريق</span>
            <span><strong>{dashboard.shipments.delivered}</strong> تم التسليم</span>
            <span><strong>{dashboard.shipments.failed}</strong> متعثر</span>
          </div>
        </article>
      </section>

      <section className="panel table-panel">
        <div className="panel-heading">
          <div><span className="section-kicker">Latest activity</span><h2>أحدث الطلبات</h2></div>
        </div>
        {dashboard.recent_orders.length ? (
          <div className="table-scroll">
            <table className="data-table">
              <thead><tr><th>الطلب</th><th>الحالة</th><th>الدفع</th><th>التنفيذ</th><th>الإجمالي</th><th>التاريخ</th></tr></thead>
              <tbody>
                {dashboard.recent_orders.map((order) => (
                  <tr key={order.id}>
                    <td className="strong-cell">{order.order_number}</td>
                    <td>{order.status}</td>
                    <td>{order.payment_status}</td>
                    <td>{order.fulfillment_status}</td>
                    <td>{formatMoney(order.total_cents, order.currency)}</td>
                    <td>{formatDate(order.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : <p className="panel-muted">لا توجد طلبات حتى الآن.</p>}
      </section>
    </>
  );
}

function Metric({ label, value, meta, tone = "normal" }: { label: string; value: number; meta: string; tone?: "normal" | "danger" }) {
  return <article className={`metric-card ${tone === "danger" ? "metric-danger" : ""}`}><span>{label}</span><strong>{value.toLocaleString("ar-EG")}</strong><small>{meta}</small></article>;
}

function MerchantEmptyState() {
  return (
    <main className="standalone-state">
      <section className="empty-panel">
        <span className="section-kicker">Merchant Admin</span>
        <h1>لا توجد شركة متاحة لهذا الحساب.</h1>
        <p>الجلسة صحيحة، لكن لا توجد عضوية نشطة داخل Tenant نشط.</p>
        <LogoutButton endpoint="/api/merchant/auth/logout" redirectTo="/merchant/login" />
      </section>
    </main>
  );
}

function formatMoney(cents: number, currency: string) {
  try {
    return new Intl.NumberFormat("ar-EG", { style: "currency", currency }).format(cents / 100);
  } catch {
    return `${(cents / 100).toFixed(2)} ${currency}`;
  }
}

function formatDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat("ar-EG", { dateStyle: "medium" }).format(date);
}
