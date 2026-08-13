"use client";

import { FormEvent, useState } from "react";

const errorMessages: Record<string, string> = {
  invalid_credentials: "البريد الإلكتروني أو كلمة المرور غير صحيحة.",
  account_locked: "الحساب مقفول مؤقتًا بسبب محاولات تسجيل دخول متكررة.",
  too_many_attempts: "عدد محاولات تسجيل الدخول كبير. حاول مرة أخرى لاحقًا.",
  mfa_challenge_missing: "انتهت جلسة التحقق الثنائي. سجّل الدخول مرة أخرى.",
  invalid_mfa_challenge: "انتهت صلاحية رمز التحقق. سجّل الدخول مرة أخرى.",
  invalid_mfa_code: "رمز التحقق غير صحيح.",
};

export function MerchantLoginForm() {
  const [mfaRequired, setMfaRequired] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submitLogin(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError(null);

    const form = new FormData(event.currentTarget);
    const response = await fetch("/api/merchant/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email: form.get("email"),
        password: form.get("password"),
      }),
    });
    const body = await response.json().catch(() => ({}));

    if (response.status === 428 && body?.mfa_required) {
      setMfaRequired(true);
      setPending(false);
      return;
    }

    if (response.ok) {
      window.location.assign("/merchant");
      return;
    }

    setError(messageFor(body?.error));
    setPending(false);
  }

  async function submitMfa(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError(null);

    const form = new FormData(event.currentTarget);
    const response = await fetch("/api/merchant/auth/mfa", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code: form.get("code") }),
    });
    const body = await response.json().catch(() => ({}));

    if (response.ok) {
      window.location.assign("/merchant");
      return;
    }

    if (body?.error === "mfa_challenge_missing" || body?.error === "invalid_mfa_challenge") {
      setMfaRequired(false);
    }

    setError(messageFor(body?.error));
    setPending(false);
  }

  if (mfaRequired) {
    return (
      <form className="auth-form" onSubmit={submitMfa}>
        <div className="form-heading">
          <span className="status-dot" />
          <div>
            <strong>التحقق بخطوتين</strong>
            <p>أدخل الرمز من تطبيق المصادقة لإكمال تسجيل الدخول.</p>
          </div>
        </div>
        <label>
          رمز التحقق
          <input name="code" inputMode="numeric" autoComplete="one-time-code" maxLength={32} required autoFocus />
        </label>
        {error ? <p className="form-error" role="alert">{error}</p> : null}
        <button className="primary-button" type="submit" disabled={pending}>
          {pending ? "جارٍ التحقق…" : "تحقق ودخول"}
        </button>
        <button className="text-button" type="button" onClick={() => { setMfaRequired(false); setError(null); }}>
          الرجوع لتسجيل الدخول
        </button>
      </form>
    );
  }

  return (
    <form className="auth-form" onSubmit={submitLogin}>
      <label>
        البريد الإلكتروني
        <input name="email" type="email" autoComplete="username" maxLength={320} required autoFocus />
      </label>
      <label>
        كلمة المرور
        <input name="password" type="password" autoComplete="current-password" maxLength={512} required />
      </label>
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      <button className="primary-button" type="submit" disabled={pending}>
        {pending ? "جارٍ تسجيل الدخول…" : "دخول لوحة التاجر"}
      </button>
    </form>
  );
}

function messageFor(code: unknown) {
  return typeof code === "string" && errorMessages[code]
    ? errorMessages[code]
    : "تعذر تسجيل الدخول. تحقق من البيانات وحاول مرة أخرى.";
}
