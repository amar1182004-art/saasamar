import Link from "next/link";
import type { ReactNode } from "react";

import { LogoutButton } from "@/components/auth/logout-button";
import type { ControlMe } from "@/lib/server/control-session";

const navigation = [
  { href: "/control", label: "نظرة عامة", key: "overview" },
  { href: "/control/tenants", label: "الشركات والمتاجر", key: "tenants" },
  { href: "/control/content", label: "المحتوى والهوية", key: "content" },
  { href: "/control/feature-flags", label: "Feature Flags", key: "flags" },
  { href: "/control/security", label: "مركز الأمان", key: "security" },
  { href: "/control/audit", label: "سجل التدقيق", key: "audit" },
] as const;

type ControlShellProps = {
  active: (typeof navigation)[number]["key"];
  me: ControlMe;
  title: string;
  kicker?: string;
  description?: string;
  actions?: ReactNode;
  children: ReactNode;
};

export function ControlShell({
  active,
  me,
  title,
  kicker = "Control plane",
  description,
  actions,
  children,
}: ControlShellProps) {
  return (
    <main className="admin-layout control-layout">
      <aside className="admin-sidebar control-sidebar">
        <div>
          <Link className="sidebar-brand" href="/">Crystell</Link>
          <span className="sidebar-caption">Super Admin</span>
        </div>
        <nav className="sidebar-nav" aria-label="Control plane navigation">
          {navigation.map((item) => (
            <Link className={item.key === active ? "nav-item active" : "nav-item"} href={item.href} key={item.key}>
              {item.label}
            </Link>
          ))}
        </nav>
        <div className="sidebar-footer">
          <span className="role-pill control-role">{me.user.role}</span>
          <LogoutButton endpoint="/api/control/auth/logout" redirectTo="/control/login" />
        </div>
      </aside>

      <section className="admin-main">
        <header className="admin-topbar">
          <div>
            <span className="section-kicker">{kicker}</span>
            <h1>{title}</h1>
            <p className="topbar-subtitle">{description ?? me.user.email}</p>
          </div>
          <div className="topbar-actions">
            {actions}
            <div className={me.session.elevated ? "topbar-status elevated" : "topbar-status"}>
              <span className="status-dot" />
              {me.session.elevated ? "صلاحيات مرتفعة" : "صلاحيات عادية"}
            </div>
          </div>
        </header>
        {children}
      </section>
    </main>
  );
}
