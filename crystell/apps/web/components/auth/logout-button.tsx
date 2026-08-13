"use client";

import { useState } from "react";

type LogoutButtonProps = {
  endpoint: "/api/merchant/auth/logout" | "/api/control/auth/logout";
  redirectTo: "/merchant/login" | "/control/login";
};

export function LogoutButton({ endpoint, redirectTo }: LogoutButtonProps) {
  const [pending, setPending] = useState(false);

  async function logout() {
    setPending(true);
    await fetch(endpoint, { method: "POST" }).catch(() => null);
    window.location.assign(redirectTo);
  }

  return (
    <button className="ghost-button" type="button" onClick={logout} disabled={pending}>
      {pending ? "جارٍ الخروج…" : "تسجيل الخروج"}
    </button>
  );
}
