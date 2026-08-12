# Phase 1 — Identity and Tenancy Status

## Implemented

- Separate PostgreSQL migration/admin credentials from restricted runtime credentials.
- `crystell_runtime` PostgreSQL group role with no login and no administrative capabilities.
- UUID identity schema for users, tenants, memberships, stores and sessions.
- Explicit runtime grants; no blanket access to all future tables.
- PostgreSQL FORCE ROW LEVEL SECURITY for tenants, memberships and stores.
- PostgreSQL FORCE ROW LEVEL SECURITY for users and sessions.
- Transaction-local `current_user_id` and `current_tenant_id` database contexts.
- Security-definer database functions for pre-authentication user and session lookup.
- Atomic initial account creation: user + tenant + owner membership + store.
- Rails models for User, Tenant, Membership, Store and Session.
- Opaque, revocable session tokens; only SHA-256 token digests are stored.
- Password hashing with bcrypt and 12-byte minimum / 72-byte maximum password policy.
- Sensitive authentication parameters filtered from Rails logs.
- Login, logout, registration and current-user API endpoints.
- MFA-aware login behavior: an MFA-enabled account is not issued a normal session by password alone.
- Tenant authorization boundary that verifies active membership before executing tenant code.
- Tenant-protected store listing endpoint.
- RSpec tenant-boundary tests that intentionally attempt cross-tenant reads and writes.
- End-to-end identity smoke test: register, authenticate, read profile, tenant access, forged tenant rejection, revoke session and re-login.

## Remaining

- Run the complete Phase 1 CI stack and fix any migration/RLS/callback issues found.
- Add login throttling and account lockout controls.
- Add email verification flow and password-reset flow.
- Add MFA enrollment/challenge/recovery-code implementation.
- Add session/device management and revoke-all-sessions behavior.
- Add tenant invitations and ownership transfer.
- Add role/permission policy layer beyond the initial owner/admin/member roles.
- Add audit events for identity and security-sensitive operations.
- Expand tenant isolation tests to background jobs, cache keys and object-storage boundaries.

Phase 1 is not complete until the security and tenant-boundary test suite is green.
