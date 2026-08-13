import Link from "next/link";
import { notFound } from "next/navigation";

import { ControlShell } from "@/components/control/control-shell";
import { requireControlSession } from "@/lib/server/control-session";
import { controlApi } from "@/lib/server/session-api";

type TenantOverview = {
  tenant: {
    id: string; name: string; slug: string; status: string;
    stores: { total: number; active: number };
    commerce: { orders: number; paid_orders: number; open_shipments: number; products: number; active_products: number };
    subscription: { status: string | null; plan_code: string | null };
    created_at: string;
  };
};

export default async function TenantPage({ params }: { params: Promise<{ id: string }> }) {
  const me = await requireControlSession();
  const { id } = await params;
  const result = await controlApi<TenantOverview>(`/control/v1/tenants/${encodeURIComponent(id)}`);
  if (result?.status === 404) notFound();
  const tenant = result?.ok ? result.data?.tenant : null;

  return (
    <ControlShell active="tenants" me={me} title={tenant?.name ?? "ملخص الشركة"} description={tenant ? `${tenant.slug} · أنشئت ${formatDate(tenant.created_at)}` : "تعذر تحميل ملخص الدعم لهذه الشركة."} actions={<Link className="secondary-link" href="/control/tenants">كل الشركات</Link>}>
      {tenant ? <>
        <section className="metric-grid">
          <Metric label="المتاجر" value={tenant.stores.total} meta={`${tenant.stores.active} نشط`} />
          <Metric label="الطلبات" value={tenant.commerce.orders} meta={`${tenant.commerce.paid_orders} مدفوع`} />
          <Metric label="المنتجات" value={tenant.commerce.products} meta={`${tenant.commerce.active_products} نشط`} />
          <Metric label="شحنات مفتوحة" value={tenant.commerce.open_shipments} meta="تحتاج متابعة" />
        </section>
        <section className="dashboard-grid two-column">
          <article className="panel"><div className="panel-heading"><div><span className="section-kicker">Tenant state</span><h2>حالة الحساب</h2></div></div><dl className="detail-list"><div><dt>الحالة</dt><dd><span className={`state-badge state-${tenant.status}`}>{tenant.status}</span></dd></div><div><dt>Tenant ID</dt><dd className="mono-value">{tenant.id}</dd></div><div><dt>Slug</dt><dd>{tenant.slug}</dd></div></dl></article>
          <article className="panel"><div className="panel-heading"><div><span className="section-kicker">Subscription</span><h2>الاشتراك الحالي</h2></div></div><dl className="detail-list"><div><dt>الخطة</dt><dd>{tenant.subscription.plan_code ?? "لا توجد خطة"}</dd></div><div><dt>الحالة</dt><dd>{tenant.subscription.status ?? "غير مشترك"}</dd></div></dl></article>
        </section>
        <section className="permission-banner"><strong>ملخص دعم للقراءة فقط.</strong><span>كل فتح لهذه الصفحة مسجل في Audit Log، ولا تمنح الصفحة وصولًا مباشرًا لقاعدة بيانات التاجر.</span></section>
      </> : <section className="permission-banner"><strong>الملخص غير متاح.</strong><span>دورك قد لا يملك tenant.support أو حدث خطأ أثناء القراءة.</span></section>}
    </ControlShell>
  );
}

function Metric({ label, value, meta }: { label: string; value: number; meta: string }) { return <article className="metric-card"><span>{label}</span><strong>{value.toLocaleString("ar-EG")}</strong><small>{meta}</small></article>; }
function formatDate(value: string) { const date = new Date(value); return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat("ar-EG", { dateStyle: "medium" }).format(date); }
