import type { ControlActionState } from "@/app/control/actions";

export function ActionFeedback({ state }: { state: ControlActionState }) {
  if (state.status === "idle") return null;
  return (
    <p className={state.status === "success" ? "form-feedback success" : "form-feedback error"} role="status">
      {state.message}
    </p>
  );
}
