# Phase 6 status — Communications and support

Status: in progress. The first Phase 6 implementation increment is ready for CI validation.

## Support conversations

- Tenant-scoped support tickets with explicit merchant read/create/manage permissions.
- Append-only conversation messages and controlled ticket status transitions.
- Merchant support inbox, ticket creation and threaded Arabic RTL conversation pages.
- Images, video and approved file types uploaded with short-lived S3-compatible signed URLs.
- Server-side upload verification for content type and declared size before a file becomes usable.
- Signed attachment previews for both merchants and authorized control-plane support staff.
- Independent control-plane support queue, conversation view, replies and status changes.
- Every control-plane queue view, ticket view, reply, status change and attachment preview is audited.
- Control-plane access uses bounded `SECURITY DEFINER` capabilities; its runtime role has no direct tenant-table access.

## Notifications and outbound channels

- Tenant-scoped in-app notification inbox with per-user visibility and read state.
- Merchant notification page with unread indicators.
- Version-safe message templates for email, SMS and WhatsApp with strict placeholder validation.
- Encrypted recipients, rendered payloads and provider credentials at rest.
- Idempotent background delivery records with retry-aware Sidekiq dispatch.
- Provider registry with a deterministic reference adapter for CI and local development.
- Email address and E.164 destination validation at the service boundary.

## Isolation and safety

- PostgreSQL RLS is enabled and forced across every Phase 6 tenant table.
- Composite tenant/store foreign keys prevent cross-scope associations.
- Support storage keys include the tenant, store and support namespace.
- Notification delivery never stores the raw recipient or rendered message in plaintext.
- Merchant members can only view the conversations they created; owners and admins can manage the store queue.

## Verification so far

- Next.js / TypeScript typecheck: passed.
- Next.js optimized production build: passed; merchant support, merchant notifications and control support routes compiled.
- React component review: passed after checking hooks, server-action authorization, serialized client props and responsive behavior.
- `git diff --check`: passed.
- A request specification now covers tenant visibility, member permissions, signed attachment lifecycle, append-only messages, encrypted idempotent delivery, in-app notifications and bounded control-plane support access.

## Remaining exit gate

Phase 6 is not marked complete until the published branch passes the complete Crystell CI matrix, including the new request specification and all prior identity, commerce and control-plane regressions.
