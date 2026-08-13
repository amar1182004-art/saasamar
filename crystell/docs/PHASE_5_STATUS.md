# Phase 5 status — Merchant and platform administration

Status: implementation complete locally; the branch CI gate is required before Phase 5 is closed.

## Merchant administration

- Secure merchant login and MFA browser flow.
- Independently revocable, HTTP-only merchant session cookies.
- Tenant and store selection limited to the authenticated membership boundary.
- Live store dashboard for orders, paid value, catalog, inventory and shipment state.
- Responsive Arabic RTL administration shell.

## Platform control plane

- Dedicated control-plane PostgreSQL runtime role, identity and session boundary.
- Mandatory MFA, persistent lockout and short-lived privilege elevation.
- Viewer, operator, admin and owner roles with explicit permissions.
- Tenant directory and read-only tenant support overview; access is audited.
- Security Center metrics with a separate `security.read` permission.
- Immutable Audit Log with bounded filters, pagination and recursive secret redaction.
- Versioned CMS/branding documents with draft, publish and rollback primitives.
- Feature flags with controlled rollout percentages and secret-like configuration rejection.
- Live Super Admin overview and operational pages for tenants, content, feature flags, security and audit history.
- Server-side mutation actions authenticate independently; Rails remains authoritative for authorization.
- Sensitive live changes require password + MFA privilege elevation and an auditable reason.

## Local validation

- Next.js / TypeScript typecheck: passed.
- Next.js optimized production build: passed; all Phase 5 routes compiled.
- `git diff --check`: passed.
- Docker Compose and Rails regression execution are unavailable in the current local runtime because Docker and Ruby are not installed. The GitHub CI matrix remains the required closure gate.

## Phase 5 exit gate

Phase 5 can be marked complete after the current branch is published and its CI matrix passes:

- production web dependency audit, typecheck and build;
- Web, API and AI container builds;
- full-stack liveness and readiness smoke tests;
- identity, MFA, session and account-lockout regressions;
- tenant, commerce and control-plane boundary specifications; and
- CMS, feature-flag, audit, security and dashboard permission specifications.

No claim is made that later phases are complete. Communications/support begins in Phase 6.
