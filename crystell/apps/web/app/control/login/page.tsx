import Link from "next/link";

import { ControlLoginForm } from "@/components/auth/control-login-form";

export default function ControlLoginPage() {
  return (
    <main className="auth-shell control-auth">
      <section className="auth-brand-panel control-brand-panel">
        <Link className="brand-mark" href="/">Crystell</Link>
        <div className="auth-brand-copy">
          <span className="section-kicker">Control plane</span>
          <h1>إدارة المنصة من نطاق أمني منفصل.</h1>
          <p>هوية مستقلة، MFA إلزامي، صلاحيات دقيقة، وسجل تدقيق لكل عملية إدارية حساسة.</p>
        </div>
        <div className="trust-row">
          <span>Separate identity</span>
          <span>Mandatory MFA</span>
          <span>Audit first</span>
        </div>
      </section>
      <section className="auth-card-wrap">
        <div className="auth-card control-card">
          <div className="auth-card-header">
            <span className="section-kicker">Super Admin</span>
            <h2>دخول الإدارة</h2>
            <p>هذه البوابة لا تقبل حسابات التجار وتستخدم جلسة مستقلة بالكامل.</p>
          </div>
          <ControlLoginForm />
          <p className="auth-note">تغييرات النشر والـFeature Flags الحساسة تتطلب Privilege Elevation إضافية.</p>
        </div>
      </section>
    </main>
  );
}
