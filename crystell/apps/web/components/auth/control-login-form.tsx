"use client";

import { FormEvent, useState } from "react";

export function ControlLoginForm() {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError(null);

    const form = new FormData(event.currentTarget);
    const response = await fetch("/api/control/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email: form.get("email"),
        password: form.get("password"),
        otp: form.get("otp"),
      }),
    });
    const body = await response.json().catch(() => ({}));

    if (response.ok) {
      window.location.assign("/control");
      return;
    }

    setError(
      body?.error === "control_plane_authentication_failed"
        ? "بيانات الدخول أو رمز التحقق غير صحيحة."
        : "تعذر الدخول إلى لوحة الإدارة. حاول مرة أخرى.",
    );
    setPending(false);
  }

  return (
    <form className="auth-form" onSubmit={submit}>
      <label>
        البريد الإداري
        <input name="email" type="email" autoComplete="username" maxLength={320} required autoFocus />
      </label>
      <label>
        كلمة المرور
        <input name="password" type="password" autoComplete="current-password" maxLength={512} required />
      </label>
      <label>
        رمز MFA
        <input name="otp" inputMode="numeric" autoComplete="one-time-code" maxLength={32} required />
      </label>
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      <button className="primary-button control-primary" type="submit" disabled={pending}>
        {pending ? "جارٍ التحقق…" : "دخول Super Admin"}
      </button>
    </form>
  );
}
