import "server-only";

import { redirect } from "next/navigation";

import { controlApi } from "@/lib/server/session-api";

export type ControlMe = {
  user: { id: string; email: string; role: string };
  session: {
    id: string;
    expires_at: string;
    elevated: boolean;
    privilege_elevated_until: string | null;
  };
};

export async function requireControlSession() {
  const result = await controlApi<ControlMe>("/control/v1/me");
  if (!result || result.status === 401 || !result.ok || !result.data) {
    redirect("/control/login");
  }

  return result.data;
}

export function canManageControl(role: string) {
  return role === "admin" || role === "owner";
}
