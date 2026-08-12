# Phase 0 Status

## Completed

- Isolated `crystell/` workspace.
- Architecture and implementation phases documented.
- Next.js + React + TypeScript web service on port 3000.
- Ruby on Rails API service on port 3001.
- Python + FastAPI AI service on port 8000.
- PostgreSQL 17, Redis 7 and MinIO in Docker Compose.
- Sidekiq worker service backed by Redis.
- Health endpoints for web, API and AI services.
- CORS configuration between web and API.
- Rails secret-key wiring.
- Crystell-specific GitHub Actions workflow covering Compose validation and container builds.

## Remaining before Phase 1

- Add database migrations and a boot-time database readiness check.
- Add automated tests for web, API and AI health endpoints.
- Add a unified developer command (`make` or task runner) for setup, start, stop and test.
- Run and fix the full CI matrix until all checks are green.
- Add baseline security headers and environment validation.

Phase 1 must not begin until these exit criteria are satisfied.
