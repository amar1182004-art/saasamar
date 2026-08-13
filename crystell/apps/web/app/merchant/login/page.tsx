import Link from "next/link";

import { MerchantLoginForm } from "@/components/auth/merchant-login-form";

export default function MerchantLoginPage() {
  return (
    <main className="auth-shell merchant-auth">
      <section className="auth-brand-panel">
        <Link className="brand-mark" href="/">Crystell</Link>
        <div className="auth-brand-copy">
          <span className="section-kicker">Merchant workspace</span>
          <h1>كل عمليات متجرك في مكان واحد.</h1>
          <p>تابع الطلبات والمخزون والمنتجات والشحن، مع عزل كامل بين الشركات والمتاجر.</p>
        </div>
        <div className="trust-row">
          <span>Tenant isolation</span>
          <span>Secure sessions</span>
          <span>MFA ready</span>
        </div>
      </section>
      <section className="auth-card-wrap">
        <div className="auth-card">
          <div className="auth-card-header">
            <span className="section-kicker">لوحة التاجر</span>
            <h2>تسجيل الدخول</h2>
            <p>استخدم حساب الشركة للوصول إلى المتاجر المسموح لك بها فقط.</p>
          </div>
          <MerchantLoginForm />
          <p className="auth-note">لن يتم حفظ رمز الجلسة داخل localStorage أو إتاحته لسكريبتات المتصفح.</p>
        </div>
      </section>
    </main>
  );
}
