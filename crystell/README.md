# Crystell

Crystell is the new commerce SaaS platform being built in this repository.

## Target architecture

- Web: Next.js + React + TypeScript
- Core API: Ruby on Rails
- AI/ML: Python + FastAPI
- Database: PostgreSQL
- Cache / jobs: Redis + Sidekiq
- Object storage: S3-compatible
- Search: PostgreSQL first, OpenSearch when justified by measured load

## Local ports

- Web: `3000`
- Rails API: `3001`
- AI service: `8000`
- PostgreSQL: `5432`
- Redis: `6379`
- MinIO API: `9000`
- MinIO console: `9001`

## Architecture principles

1. Modular monolith for the commerce core.
2. Multi-tenant isolation enforced in both application code and PostgreSQL RLS.
3. Stateless web/API instances so the platform can scale horizontally.
4. AI is isolated from the checkout/order critical path.
5. No permanent local file storage.
6. Background work is queued and idempotent.
7. Every sensitive operation is auditable.
8. Production infrastructure is replaceable; business logic must not depend on a single hosting provider.

See `docs/PHASES.md` and `docs/ARCHITECTURE.md` for the implementation plan.