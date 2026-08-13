#!/bin/sh
set -eu

: "${APP_DATABASE_USER:=crystell_app}"
: "${APP_DATABASE_PASSWORD:=change-me-app-local-only}"
: "${CONTROL_PLANE_DATABASE_USER:=crystell_control_app}"
: "${CONTROL_PLANE_DATABASE_PASSWORD:=change-me-control-local-only}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'crystell_runtime') THEN
    CREATE ROLE crystell_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'crystell_control_plane_runtime') THEN
    CREATE ROLE crystell_control_plane_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = '${APP_DATABASE_USER}') THEN
    CREATE ROLE ${APP_DATABASE_USER} LOGIN PASSWORD '${APP_DATABASE_PASSWORD}' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = '${CONTROL_PLANE_DATABASE_USER}') THEN
    CREATE ROLE ${CONTROL_PLANE_DATABASE_USER} LOGIN PASSWORD '${CONTROL_PLANE_DATABASE_PASSWORD}' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT;
  END IF;
END
\$\$;

GRANT crystell_runtime TO ${APP_DATABASE_USER};
GRANT crystell_control_plane_runtime TO ${CONTROL_PLANE_DATABASE_USER};
REVOKE crystell_runtime FROM ${CONTROL_PLANE_DATABASE_USER};

GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO crystell_runtime;
GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO crystell_control_plane_runtime;
GRANT USAGE ON SCHEMA public TO crystell_runtime;
GRANT USAGE ON SCHEMA public TO crystell_control_plane_runtime;
EOSQL
