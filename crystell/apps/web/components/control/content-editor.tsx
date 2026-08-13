"use client";

import { useActionState } from "react";

import { publishContent, saveContentDraft, type ControlActionState } from "@/app/control/actions";
import { ActionFeedback } from "@/components/control/action-feedback";

type DocumentInput = {
  key: string;
  kind: string;
  locale: string;
  draft_content: Record<string, unknown>;
  draft_version: number;
  published_version: number;
} | null;

const initialState: ControlActionState = { status: "idle", message: "" };

export function ContentEditor({ document }: { document: DocumentInput }) {
  const [saveState, saveAction, saving] = useActionState(saveContentDraft, initialState);
  const [publishState, publishAction, publishing] = useActionState(publishContent, initialState);
  const key = document?.key ?? "";
  const locale = document?.locale ?? "ar";

  return (
    <div className="editor-stack">
      <form action={saveAction} className="control-form panel">
        <div className="panel-heading">
          <div><span className="section-kicker">Draft editor</span><h2>{document ? `تعديل ${document.key}` : "مستند محتوى جديد"}</h2></div>
          {document ? <span className="counter-badge">v{document.draft_version}</span> : null}
        </div>
        <div className="form-grid three">
          <label>المفتاح<input name="key" defaultValue={key} placeholder="home.hero" pattern="[a-z0-9][a-z0-9._-]{0,119}" readOnly={Boolean(document)} required /></label>
          <label>النوع<select name="kind" defaultValue={document?.kind ?? "page"}><option value="page">Page</option><option value="branding">Branding</option><option value="banner">Banner</option><option value="navigation">Navigation</option><option value="footer">Footer</option><option value="ad">Ad</option></select></label>
          <label>اللغة<input name="locale" defaultValue={locale} pattern="[a-z]{2,3}(-[A-Z]{2})?" required /></label>
        </div>
        <label>المحتوى بصيغة JSON<textarea name="content" rows={14} defaultValue={JSON.stringify(document?.draft_content ?? { title: "", sections: [] }, null, 2)} required /></label>
        <label>سبب التعديل<input name="reason" maxLength={500} placeholder="وصف مختصر للتغيير" /></label>
        <div className="form-actions"><button className="control-action-button" disabled={saving} type="submit">{saving ? "جارٍ الحفظ…" : "حفظ مسودة جديدة"}</button></div>
        <ActionFeedback state={saveState} />
      </form>

      {document && document.draft_version > document.published_version ? (
        <form action={publishAction} className="publish-strip">
          <input name="key" type="hidden" value={document.key} />
          <input name="locale" type="hidden" value={document.locale} />
          <div><strong>هناك مسودة غير منشورة</strong><small>v{document.published_version} live · v{document.draft_version} draft</small></div>
          <input name="reason" maxLength={500} placeholder="سبب النشر (مطلوب)" required />
          <button className="control-action-button warning" disabled={publishing} type="submit">{publishing ? "جارٍ النشر…" : "نشر النسخة الحية"}</button>
          <ActionFeedback state={publishState} />
        </form>
      ) : null}
    </div>
  );
}
