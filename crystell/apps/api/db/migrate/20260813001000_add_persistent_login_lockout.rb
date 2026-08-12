class AddPersistentLoginLockout < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :failed_login_count, :integer, null: false, default: 0
    add_column :users, :last_failed_login_at, :datetime
    add_column :users, :locked_until, :datetime

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.record_login_failure(
        p_email text,
        p_threshold integer,
        p_lock_seconds integer
      )
      RETURNS timestamp without time zone
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
      DECLARE
        v_user_id uuid;
        v_failed_count integer;
        v_locked_until timestamp without time zone;
      BEGIN
        SELECT u.id, u.failed_login_count, u.locked_until
        INTO v_user_id, v_failed_count, v_locked_until
        FROM public.users u
        WHERE u.email = p_email::public.citext
          AND u.status = 'active'
        LIMIT 1
        FOR UPDATE;

        IF v_user_id IS NULL THEN
          RETURN NULL;
        END IF;

        IF v_locked_until IS NOT NULL AND v_locked_until > CURRENT_TIMESTAMP THEN
          RETURN v_locked_until;
        END IF;

        v_failed_count := COALESCE(v_failed_count, 0) + 1;

        IF v_failed_count >= GREATEST(p_threshold, 1) THEN
          v_locked_until := CURRENT_TIMESTAMP + make_interval(secs => GREATEST(p_lock_seconds, 1));
          v_failed_count := 0;
        ELSE
          v_locked_until := NULL;
        END IF;

        UPDATE public.users
        SET failed_login_count = v_failed_count,
            last_failed_login_at = CURRENT_TIMESTAMP,
            locked_until = v_locked_until,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = v_user_id;

        RETURN v_locked_until;
      END
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.record_login_success(p_user_id uuid)
      RETURNS void
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
      BEGIN
        UPDATE public.users
        SET failed_login_count = 0,
            last_failed_login_at = NULL,
            locked_until = NULL,
            last_signed_in_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_user_id;
      END
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION crystell.record_login_failure(text,integer,integer) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.record_login_failure(text,integer,integer) TO crystell_runtime"
    execute "REVOKE ALL ON FUNCTION crystell.record_login_success(uuid) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.record_login_success(uuid) TO crystell_runtime"

    execute "DROP FUNCTION IF EXISTS crystell.user_for_password_auth(text)"
    execute <<~SQL
      CREATE FUNCTION crystell.user_for_password_auth(p_email text)
      RETURNS TABLE(
        id uuid,
        email text,
        password_digest text,
        status text,
        mfa_enabled boolean,
        locked_until timestamp without time zone
      )
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
        SELECT u.id, u.email::text, u.password_digest, u.status, u.mfa_enabled, u.locked_until
        FROM public.users u
        WHERE u.email = p_email::public.citext
        LIMIT 1
      $$
    SQL
    execute "REVOKE ALL ON FUNCTION crystell.user_for_password_auth(text) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.user_for_password_auth(text) TO crystell_runtime"
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.record_login_success(uuid)"
    execute "DROP FUNCTION IF EXISTS crystell.record_login_failure(text,integer,integer)"
    execute "DROP FUNCTION IF EXISTS crystell.user_for_password_auth(text)"

    remove_column :users, :locked_until
    remove_column :users, :last_failed_login_at
    remove_column :users, :failed_login_count

    execute <<~SQL
      CREATE FUNCTION crystell.user_for_password_auth(p_email text)
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
    execute "REVOKE ALL ON FUNCTION crystell.user_for_password_auth(text) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.user_for_password_auth(text) TO crystell_runtime"
  end
end
