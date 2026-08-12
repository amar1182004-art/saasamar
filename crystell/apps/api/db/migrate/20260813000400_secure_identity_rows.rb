class SecureIdentityRows < ActiveRecord::Migration[8.0]
  def up
    execute "CREATE SCHEMA IF NOT EXISTS crystell"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.current_user_id()
      RETURNS uuid
      LANGUAGE sql
      STABLE
      AS $$
        SELECT NULLIF(current_setting('app.current_user_id', true), '')::uuid
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.user_for_password_auth(p_email text)
      RETURNS TABLE(
        id uuid,
        email text,
        password_digest text,
        status text,
        mfa_enabled boolean
      )
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
        SELECT u.id, u.email::text, u.password_digest, u.status, u.mfa_enabled
        FROM public.users u
        WHERE u.email = p_email::public.citext
        LIMIT 1
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.active_session_by_digest(p_digest text)
      RETURNS TABLE(
        session_id uuid,
        user_id uuid,
        expires_at timestamp without time zone
      )
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
        SELECT s.id, s.user_id, s.expires_at
        FROM public.sessions s
        WHERE s.token_digest = p_digest
          AND s.revoked_at IS NULL
          AND s.expires_at > CURRENT_TIMESTAMP
        LIMIT 1
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION crystell.user_for_password_auth(text) FROM PUBLIC"
    execute "REVOKE ALL ON FUNCTION crystell.active_session_by_digest(text) FROM PUBLIC"
    execute "GRANT USAGE ON SCHEMA crystell TO crystell_runtime"
    execute "GRANT EXECUTE ON FUNCTION crystell.current_user_id() TO crystell_runtime"
    execute "GRANT EXECUTE ON FUNCTION crystell.user_for_password_auth(text) TO crystell_runtime"
    execute "GRANT EXECUTE ON FUNCTION crystell.active_session_by_digest(text) TO crystell_runtime"

    execute "ALTER TABLE users ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE users FORCE ROW LEVEL SECURITY"
    execute <<~SQL
      CREATE POLICY user_self_access ON users
      FOR ALL
      TO crystell_runtime
      USING (id = crystell.current_user_id())
      WITH CHECK (id = crystell.current_user_id())
    SQL

    execute "ALTER TABLE sessions ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE sessions FORCE ROW LEVEL SECURITY"
    execute <<~SQL
      CREATE POLICY session_self_access ON sessions
      FOR ALL
      TO crystell_runtime
      USING (user_id = crystell.current_user_id())
      WITH CHECK (user_id = crystell.current_user_id())
    SQL

    %w[users sessions].each do |table|
      execute <<~SQL
        DO $$
        BEGIN
          EXECUTE format(
            'CREATE POLICY migration_admin_access ON #{table} FOR ALL TO %I USING (true) WITH CHECK (true)',
            current_user
          );
        END
        $$
      SQL
    end
  end

  def down
    %w[users sessions].each do |table|
      execute "DROP POLICY IF EXISTS migration_admin_access ON #{table}"
    end

    execute "DROP POLICY IF EXISTS user_self_access ON users"
    execute "DROP POLICY IF EXISTS session_self_access ON sessions"
    execute "ALTER TABLE users NO FORCE ROW LEVEL SECURITY"
    execute "ALTER TABLE users DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE sessions NO FORCE ROW LEVEL SECURITY"
    execute "ALTER TABLE sessions DISABLE ROW LEVEL SECURITY"

    execute "DROP FUNCTION IF EXISTS crystell.active_session_by_digest(text)"
    execute "DROP FUNCTION IF EXISTS crystell.user_for_password_auth(text)"
    execute "DROP FUNCTION IF EXISTS crystell.current_user_id()"
  end
end
