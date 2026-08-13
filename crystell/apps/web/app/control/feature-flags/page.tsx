import Link from "next/link";

import { ControlShell } from "@/components/control/control-shell";
import { ElevationForm } from "@/components/control/elevation-form";
import { FeatureFlagEditor } from "@/components/control/feature-flag-editor";
import { canManageControl, requireControlSession } from "@/lib/server/control-session";
import { controlApi } from "@/lib/server/session-api";

type FeatureFlag = { id: string; key: string; description: string | null; enabled: boolean; rollout_percentage: number; config: Record<string, unknown>; updated_at: string };
type FeatureFlagResponse = { feature_flags: FeatureFlag[] };

export default async function FeatureFlagsPage({ searchParams }: { searchParams: Promise<{ key?: string }> }) {
  const me = await requireControlSession();
  const selectedKey = (await searchParams).key?.slice(0, 120);
  const result = await controlApi<FeatureFlagResponse>("/control/v1/feature-flags");
  const flags = result?.ok ? result.data?.feature_flags ?? [] : [];
  const selected = flags.find((flag) => flag.key === selectedKey) ?? null;
  const canManage = canManageControl(me.user.role);

  return <ControlShell active="flags" me={me} title="Feature Flags" description="إدارة الإطلاق التدريجي بدون تخزين أسرار داخل إعدادات الأعلام.">
    {canManage && !me.session.elevated ? <ElevationForm /> : null}
    <section className="management-layout"><aside className="panel management-list"><div className="panel-heading"><div><span className="section-kicker">Flags</span><h2>الإطلاقات</h2></div><span className="counter-badge">{flags.length}</span></div>
      {canManage ? <Link className={!selectedKey ? "management-item active" : "management-item"} href="/control/feature-flags">+ علم جديد</Link> : null}
      {flags.map((flag) => <Link className={flag.key === selected?.key ? "management-item active" : "management-item"} href={`/control/feature-flags?key=${encodeURIComponent(flag.key)}`} key={flag.id}><span><strong>{flag.key}</strong><small>{flag.description ?? "بدون وصف"}</small></span><span className={flag.enabled ? "state-badge state-active" : "state-badge"}>{flag.enabled ? `${flag.rollout_percentage}%` : "off"}</span></Link>)}
      {!flags.length ? <p className="panel-muted">لا توجد Feature Flags بعد.</p> : null}
    </aside><div>{canManage ? <FeatureFlagEditor flag={selected} /> : <section className="permission-banner"><strong>وضع القراءة فقط.</strong><span>دور {me.user.role} يستطيع مراجعة الأعلام لكنه لا يملك feature_flags.manage.</span></section>}</div></section>
  </ControlShell>;
}
