#!/bin/sh
set -eu

: "${APP_DATABASE_USER:=crystell_app}"
: "${APP_DATABASE_PASSWORD:=change-me-app-local-only}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'crystell_runtime') THEN
    CREATE ROLE crystell_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = '${APP_DATABASE_USER}') THEN
    CREATE ROLE ${APP_DATABASE_USER} LOGIN PASSWORD '${APP_DATABASE_PASSWORD}' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT;
  END IF;
END
\$\$;

GRANT crystell_runtime TO ${APP_DATABASE_USER};
GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO crystell_runtime;
GRANT USAGE ON SCHEMA public TO crystell_runtime;
EOSQL
