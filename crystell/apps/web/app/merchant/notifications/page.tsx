import { markNotificationRead } from "@/app/merchant/notifications/actions";
import { MerchantShell } from "@/components/merchant/merchant-shell";
import { loadMerchantContext } from "@/lib/server/merchant-context";
import { merchantApi } from "@/lib/server/session-api";

type Notification = {
  id: string;
  kind: string;
  title: string;
  body: string;
  action_url: string | null;
  read_at: string | null;
  created_at: string;
};

type PageProps = { searchParams: Promise<{ tenant?: string; store?: string }> };

export default async function MerchantNotificationsPage({ searchParams }: PageProps) {
  const query = await searchParams;
  const context = await loadMerchantContext(query);
  const { tenants, selectedTenant, stores, selectedStore, role } = context;
  if (!selectedTenant) return <main className="standalone-state"><section className="empty-panel"><strong>لا توجد شركة متاحة لهذا الحساب.</strong></section></main>;

  const result = await merchantApi<{ notifications: Notification[] }>("/v1/notifications", selectedTenant.id);
  const notifications = result?.ok ? result.data?.notifications ?? [] : [];
  const unread = notifications.filter((notification) => !notification.read_at).length;

  return (
    <MerchantShell active="notifications" tenants={tenants} selectedTenant={selectedTenant} stores={stores} selectedStore={selectedStore} role={role} title="الإشعارات" description="تنبيهات الحساب والمتجر مرتبة من الأحدث.">
      <section className="panel notification-inbox">
        <div className="panel-heading"><div><span className="section-kicker">In-app inbox</span><h2>صندوق الإشعارات</h2></div><span className="counter-badge">{unread} جديد</span></div>
        {result?.status === 403 ? <p className="panel-muted">حسابك لا يملك صلاحية قراءة الإشعارات.</p> : notifications.length ? (
          <div className="notification-stack">
            {notifications.map((notification) => (
              <article className={notification.read_at ? "notification-card is-read" : "notification-card"} key={notification.id}>
                <span className="notification-mark" />
                <div><span className="ticket-number">{notification.kind}</span><h3>{notification.title}</h3><p>{notification.body}</p><time>{formatDateTime(notification.created_at)}</time></div>
                {!notification.read_at ? (
                  <form action={markNotificationRead}>
                    <input type="hidden" name="tenant_id" value={selectedTenant.id} />
                    <input type="hidden" name="notification_id" value={notification.id} />
                    <button className="ghost-button" type="submit">تحديد كمقروء</button>
                  </form>
                ) : <span className="state-badge state-active">مقروء</span>}
              </article>
            ))}
          </div>
        ) : <p className="panel-muted">لا توجد إشعارات حتى الآن.</p>}
      </section>
    </MerchantShell>
  );
}

function formatDateTime(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat("ar-EG", { dateStyle: "medium", timeStyle: "short" }).format(date);
}
