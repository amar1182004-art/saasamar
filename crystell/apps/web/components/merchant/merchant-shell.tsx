import Link from "next/link";
import type { ReactNode } from "react";

import { LogoutButton } from "@/components/auth/logout-button";
import type { MerchantStore, MerchantTenant } from "@/lib/server/merchant-context";

const navigation = [
  { path: "/merchant", label: "الرئيسية", key: "overview" },
  { path: "/merchant/support", label: "الدعم", key: "support" },
  { path: "/merchant/notifications", label: "الإشعارات", key: "notifications" },
] as const;

type MerchantShellProps = {
  active: (typeof navigation)[number]["key"];
  tenants: MerchantTenant[];
  selectedTenant: MerchantTenant;
  stores: MerchantStore[];
  selectedStore: MerchantStore | null;
  role: string;
  title: string;
  description?: string;
  children: ReactNode;
};

export function MerchantShell({
  active,
  tenants,
  selectedTenant,
  stores,
  selectedStore,
  role,
  title,
  description,
  children,
}: MerchantShellProps) {
  const contextQuery = merchantQuery(selectedTenant.id, selectedStore?.id);
  const activePath = navigation.find((item) => item.key === active)?.path ?? "/merchant";

  return (
    <main className="admin-layout">
      <aside className="admin-sidebar merchant-sidebar">
        <div>
          <Link className="sidebar-brand" href="/">Crystell</Link>
          <span className="sidebar-caption">Merchant Admin</span>
        </div>
        <nav className="sidebar-nav" aria-label="Merchant navigation">
          {navigation.map((item) => (
            <Link className={item.key === active ? "nav-item active" : "nav-item"} href={`${item.path}?${contextQuery}`} key={item.key}>
              {item.label}
            </Link>
          ))}
          <span className="nav-item muted-nav">المنتجات</span>
          <span className="nav-item muted-nav">الطلبات</span>
          <span className="nav-item muted-nav">المخزون</span>
          <span className="nav-item muted-nav">الشحن</span>
          <span className="nav-item muted-nav">الفوترة</span>
        </nav>
        <div className="sidebar-footer">
          <span className="role-pill">{role}</span>
          <LogoutButton endpoint="/api/merchant/auth/logout" redirectTo="/merchant/login" />
        </div>
      </aside>

      <section className="admin-main">
        <header className="admin-topbar">
          <div>
            <span className="section-kicker">Merchant workspace</span>
            <h1>{title}</h1>
            {description ? <p className="topbar-subtitle">{description}</p> : null}
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
                  href={`${activePath}?${merchantQuery(tenant.id)}`}
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
                    href={`${activePath}?${merchantQuery(selectedTenant.id, store.id)}`}
                    key={store.id}
                  >
                    {store.name}
                  </Link>
                ))}
              </div>
            </div>
          ) : null}
        </div>
        {children}
      </section>
    </main>
  );
}

function merchantQuery(tenantId: string, storeId?: string) {
  const query = new URLSearchParams({ tenant: tenantId });
  if (storeId) query.set("store", storeId);
  return query.toString();
}
