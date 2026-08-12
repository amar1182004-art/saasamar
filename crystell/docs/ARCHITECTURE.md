# Crystell architecture

## Core stack

- Next.js + React + TypeScript for public web, storefront shell and dashboards.
- Ruby on Rails for the commerce core and business rules.
- PostgreSQL as the source of truth.
- Redis + Sidekiq for cache, rate limiting and background jobs.
- Python + FastAPI for AI/ML, OCR and document/image analysis.
- S3-compatible object storage for user files and media.

## Service boundaries

### Web
Owns rendering and browser UX. It must not contain privileged business rules or provider secrets.

### Rails core
Owns users, tenants, stores, catalog, inventory, plans, billing state, orders, payments orchestration, shipping orchestration, permissions and audit records.

### Python AI service
Owns inference-oriented workloads only. It must not become a second system of record for commerce data. Failure of the AI service must not stop checkout, orders or payments.

## Multi-tenancy

All tenant-owned relational tables carry a non-null `tenant_id`. Sensitive paths may also carry `store_id` where a tenant owns multiple stores.

Tenant isolation is enforced at several layers:

1. Authenticated tenant context in Rails.
2. Authorization policies for every protected action.
3. PostgreSQL Row-Level Security for tenant-owned tables.
4. Tenant-prefixed Redis keys.
5. Tenant/store namespaces in object storage.
6. Tenant-scoped search and AI namespaces.
7. Tenant-bound audit logs.

The runtime database role must not be SUPERUSER and must not have BYPASSRLS. Migration credentials are separate from runtime credentials.

## Scaling model

Public storefront content should be CDN-cacheable wherever correctness allows. Application servers are stateless and horizontally scalable. PostgreSQL remains the system of record, with PgBouncer, backups and replicas introduced based on measured needs. Heavy reports, imports, notifications and AI work run asynchronously.

## Security baseline

- TLS everywhere outside the local development network.
- Secrets only through environment/secret managers; never committed.
- MFA required for privileged platform administration.
- CSRF protection and secure HTTP-only cookies where cookie sessions are used.
- Rate limiting on authentication, public APIs and expensive actions.
- Signed/idempotent inbound webhooks.
- Signed outbound webhooks with delivery tracking.
- Application-level encryption for selected highly sensitive fields.
- Private object storage and short-lived signed URLs.
- Immutable audit trail for security-sensitive administration.

## Enterprise isolation

Standard plans use pooled infrastructure with strong logical isolation. Enterprise customers may be provisioned with progressively stronger isolation, including a dedicated database, Redis, storage namespace/key, or a fully dedicated environment. The application must avoid provider-specific assumptions so these deployment modes do not require rewriting business logic.
