# Crystell implementation phases

## Phase 0 — Foundation
- Repository layout for web, API, AI and infrastructure.
- Docker-based local development.
- Environment conventions and secret handling rules.
- CI for lint/build/test.
- Health endpoints.
- Initial observability hooks.
- Architecture decision records.

Exit criteria: all services boot locally, CI is green, no secrets are committed, and the repository structure is documented.

## Phase 1 — Identity and tenancy
- Users, sessions and hardened authentication.
- Persistent login throttling/account lockout.
- TOTP MFA, recovery codes and sensitive re-authentication.
- Email verification and password-reset delivery primitives.
- Tenants, stores, memberships, invitations and ownership transfer.
- Tenant context propagation across requests, services, jobs, cache keys and storage namespaces.
- PostgreSQL Row-Level Security with a restricted runtime database role.
- Append-only security audit events.
- Direct database and end-to-end tenant boundary tests.

Exit criteria: authentication/MFA/session flows pass end-to-end tests; PostgreSQL rejects direct cross-tenant reads/writes under the runtime role; tenant context cannot leak across nested service scopes, jobs, Redis/cache namespaces or object-storage keys; identity delivery does not reveal account existence; production web dependencies have no known high-severity audit findings; and the complete Crystell CI matrix is green.

## Phase 2 — Plans and billing
- Plans, entitlements and feature limits.
- Monthly/annual subscriptions.
- Coupons, affiliate/blogger codes and commissions.
- Invoices, usage metering and billing audit trail.

## Phase 3 — Commerce catalog
- Stores, products, variants and categories.
- Inventory and stock movements.
- Media and S3-compatible storage.
- Storefront configuration.

## Phase 4 — Orders, payments and shipping
- Cart, checkout and orders.
- Payment-provider abstraction.
- Shipping-provider abstraction.
- Webhooks, idempotency and reconciliation.

## Phase 5 — Merchant and platform admin
- Merchant dashboard.
- Super-admin dashboard.
- Audit logs and security center.
- CMS, branding and feature flags.

## Phase 6 — Communications and support
- In-app support chat with files, images and video.
- Email, SMS and WhatsApp provider abstractions.
- Tickets, notifications and message templates.

## Phase 7 — AI and Python services
- AI gateway.
- OCR/document analysis.
- Identity/document matching workflows.
- Recommendations, classification and anomaly signals.
- Strict tenant-scoped vector/document namespaces.

## Phase 8 — SEO / AEO / GEO and CMS
- Store SEO tooling.
- Structured data.
- AI-assisted content workflows.
- CMS pages, blog, banners and navigation.

## Phase 9 — Partners and developers
- Freelancer and agency plans.
- Partner dashboard.
- API keys, webhooks and sandbox.
- Marketplace foundations.

## Phase 10 — Advanced security
- Encryption strategy.
- Dedicated tenant options.
- Key rotation, security alerts and approval workflows.
- Backup/restore drills.

## Phase 11 — Performance and scale
- CDN/cache strategy.
- Load tests up to launch targets.
- Database tuning and partitioning where justified.
- Horizontal scaling runbooks.

Launch design target: 20,000 subscribed tenants, millions of monthly visits, and a tested peak concurrency target rather than an unverified marketing number.

## Phase 12 — Production readiness
- Production deployment.
- Monitoring, alerting and incident runbooks.
- Disaster recovery.
- Release process and rollback.
