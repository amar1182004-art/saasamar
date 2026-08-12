# Phase 0 Status

## Completed

- Isolated `crystell/` workspace.
- Architecture and implementation phases documented.
- Next.js + React + TypeScript web service on port 3000.
- Ruby on Rails API service on port 3001.
- Python + FastAPI AI service on port 8000.
- PostgreSQL 17, Redis 7 and MinIO in Docker Compose.
- Sidekiq worker service backed by Redis.
- Liveness and readiness endpoints for web, API and AI services.
- API readiness verifies PostgreSQL and Redis connectivity.
- Baseline PostgreSQL migration enabling `pgcrypto`.
- Automatic `rails db:prepare` before API startup.
- Worker waits for API readiness before starting.
- CORS configuration between web and API.
- Security headers for Rails and Next.js.
- Production secret validation.
- Unified Makefile commands for setup, start, stop, logs and testing.
- Full-stack smoke test covering health and readiness endpoints.
- Crystell-specific GitHub Actions workflow covering Compose validation, container builds and full-stack smoke testing.

## Exit criterion

Phase 0 is complete when the latest GitHub Actions matrix is green after these changes.

Phase 1 must not begin before that final CI verification.
