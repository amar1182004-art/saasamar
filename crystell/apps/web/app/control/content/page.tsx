import Link from "next/link";

import { ContentEditor } from "@/components/control/content-editor";
import { ControlShell } from "@/components/control/control-shell";
import { ElevationForm } from "@/components/control/elevation-form";
import { canManageControl, requireControlSession } from "@/lib/server/control-session";
import { controlApi } from "@/lib/server/session-api";

type ContentDocument = { id: string; key: string; kind: string; locale: string; draft_content: Record<string, unknown>; published_content: Record<string, unknown>; draft_version: number; published_version: number; published_at: string | null; updated_at: string };
type ContentResponse = { content_documents: ContentDocument[] };

export default async function ContentPage({ searchParams }: { searchParams: Promise<{ key?: string }> }) {
  const me = await requireControlSession();
  const selectedKey = (await searchParams).key?.slice(0, 120);
  const result = await controlApi<ContentResponse>("/control/v1/content");
  const documents = result?.ok ? result.data?.content_documents ?? [] : [];
  const selected = documents.find((document) => document.key === selectedKey) ?? null;
  const canManage = canManageControl(me.user.role);

  return <ControlShell active="content" me={me} title="المحتوى والهوية" description="CMS داخلي بمسودات وإصدارات منشورة، مع سجل كامل لكل تعديل.">
    {canManage && !me.session.elevated ? <ElevationForm /> : null}
    <section className="management-layout">
      <aside className="panel management-list"><div className="panel-heading"><div><span className="section-kicker">Documents</span><h2>المستندات</h2></div><span className="counter-badge">{documents.length}</span></div>
        {canManage ? <Link className={!selectedKey ? "management-item active" : "management-item"} href="/control/content">+ مستند جديد</Link> : null}
        {documents.map((document) => <Link className={document.key === selected?.key ? "management-item active" : "management-item"} href={`/control/content?key=${encodeURIComponent(document.key)}`} key={document.id}><span><strong>{document.key}</strong><small>{document.kind} · {document.locale}</small></span><span className={document.draft_version === document.published_version ? "state-badge state-active" : "state-badge state-warning"}>v{document.published_version}/{document.draft_version}</span></Link>)}
        {!documents.length ? <p className="panel-muted">لا توجد مستندات بعد.</p> : null}
      </aside>
      <div>{canManage ? <ContentEditor document={selected} /> : <section className="permission-banner"><strong>وضع القراءة فقط.</strong><span>دور {me.user.role} يستطيع مراجعة قائمة المحتوى لكنه لا يملك content.manage.</span></section>}</div>
    </section>
  </ControlShell>;
}
