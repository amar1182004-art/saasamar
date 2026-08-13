# Phase 1 — Identity and Tenancy Status

## Implemented

- Separate PostgreSQL migration/admin credentials from restricted runtime credentials.
- `crystell_runtime` PostgreSQL group role with no login and no administrative capabilities.
- UUID identity schema for users, tenants, memberships, stores and sessions.
- Explicit runtime grants; no blanket access to future tables.
- PostgreSQL FORCE ROW LEVEL SECURITY for tenants, memberships and stores.
- PostgreSQL FORCE ROW LEVEL SECURITY for users, sessions and MFA credentials.
- Transaction-local `current_user_id` and `current_tenant_id` database contexts.
- Security-definer database functions for pre-authentication user/session lookup.
- Atomic initial account creation: user + tenant + owner membership + store.
- Rails models for User, Tenant, Membership, Store, Session and MFA credentials.
- Opaque revocable session tokens; only SHA-256 token digests are stored.
- Password hashing with bcrypt and 12-byte minimum / 72-byte maximum password policy.
- Constant-cost dummy bcrypt verification for unknown accounts to reduce timing-based account enumeration.
- Parameterized account-registration database calls so password hashes are not interpolated into SQL logs.
- Credential derivatives, MFA secrets/codes and authorization headers filtered from Rails logs.
- Registration, login, logout and current-user API endpoints.
- Redis-backed login throttling for email/IP and IP-wide abuse, using HMAC fingerprints instead of raw identifiers.
- Atomic Redis counter expiry and MFA challenge lifecycle to avoid race-created permanent keys.
- TOTP MFA enrollment and confirmation.
- AES-256-GCM encryption for stored TOTP secrets.
- One-time recovery codes stored only as HMAC digests.
- Short-lived one-time MFA login challenges in Redis with attempt limits.
- TOTP replay protection using the last accepted timestep.
- MFA-aware login: password authentication alone cannot issue a normal session once MFA is enabled.
- User session/device listing, individual revocation and revoke-all-other-sessions endpoints.
- Tenant authorization boundary that verifies active membership before tenant code executes.
- Explicit owner/admin/member permission matrix.
- Tenant-protected store listing requiring the `stores.read` permission.
- PostgreSQL tenant-boundary tests for cross-tenant reads and raw SQL writes that bypass Rails validations.
- Permission-boundary tests for owner/admin/member and suspended memberships.
- End-to-end smoke coverage for registration, authentication, forged tenant rejection, logout, throttling, MFA, recovery-code one-time use and session revocation.
- One-time identity token schema for email verification and password reset.
- Security-definer database operations for issuing/consuming verification and reset tokens; password reset revokes existing sessions.
- Append-only security event table with no runtime table permissions.
- Security-definer audit append function and audit events for session creation/revocation and MFA enablement.

## Remaining

- Run the newest complete Phase 1 CI matrix and fix any remaining migration/RLS/integration issues.
- Add persistent account lockout/escalation policy beyond Redis request throttling.
- Expose email verification and password-reset HTTP flows and connect them to the later email delivery/outbox layer without leaking tokens.
- Add MFA disable/recovery-code regeneration flows with re-authentication requirements.
- Add tenant invitations and secure ownership transfer.
- Expand authorization tests to every future tenant-sensitive controller as those modules are added.
- Expand tenant isolation tests to background jobs, Redis/cache keys and object-storage namespaces.
- Add production-grade security event retention/export controls for the platform security team.

Phase 1 remains a draft until the latest identity, MFA, permission and PostgreSQL boundary matrix is green.
