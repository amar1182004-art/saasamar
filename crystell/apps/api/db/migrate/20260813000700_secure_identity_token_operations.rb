class SecureIdentityTokenOperations < ActiveRecord::Migration[8.0]
  def up
    execute "ALTER TABLE identity_tokens ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE identity_tokens FORCE ROW LEVEL SECURITY"

    execute <<~SQL
      DO $$
      BEGIN
        EXECUTE format(
          'CREATE POLICY migration_admin_access ON identity_tokens FOR ALL TO %I USING (true) WITH CHECK (true)',
          current_user
        );
      END
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.issue_identity_token(
        p_email text,
        p_purpose text,
        p_token_digest text,
        p_expires_at timestamp without time zone
      )
      RETURNS boolean
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
      DECLARE
        v_user_id uuid;
      BEGIN
        IF p_purpose NOT IN ('email_verification', 'password_reset') THEN
          RAISE EXCEPTION 'invalid identity token purpose';
        END IF;

        SELECT u.id INTO v_user_id
        FROM public.users u
        WHERE u.email = p_email::public.citext
          AND u.status = 'active'
        LIMIT 1;

        IF v_user_id IS NULL THEN
          RETURN false;
        END IF;

        UPDATE public.identity_tokens
        SET consumed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
        WHERE user_id = v_user_id
          AND purpose = p_purpose
          AND consumed_at IS NULL;

        INSERT INTO public.identity_tokens (
          id, user_id, purpose, token_digest, expires_at, created_at, updated_at
        ) VALUES (
          gen_random_uuid(), v_user_id, p_purpose, p_token_digest, p_expires_at,
          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        );

        RETURN true;
      END
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.consume_email_verification(p_token_digest text)
      RETURNS boolean
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
      DECLARE
        v_token_id uuid;
        v_user_id uuid;
      BEGIN
        SELECT t.id, t.user_id INTO v_token_id, v_user_id
        FROM public.identity_tokens t
        WHERE t.token_digest = p_token_digest
          AND t.purpose = 'email_verification'
          AND t.consumed_at IS NULL
          AND t.expires_at > CURRENT_TIMESTAMP
        FOR UPDATE;

        IF v_token_id IS NULL THEN
          RETURN false;
        END IF;

        UPDATE public.users
        SET email_verified_at = COALESCE(email_verified_at, CURRENT_TIMESTAMP),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = v_user_id;

        UPDATE public.identity_tokens
        SET consumed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
        WHERE id = v_token_id;

        RETURN true;
      END
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.consume_password_reset(
        p_token_digest text,
        p_password_digest text
      )
      RETURNS boolean
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
      DECLARE
        v_token_id uuid;
        v_user_id uuid;
      BEGIN
        SELECT t.id, t.user_id INTO v_token_id, v_user_id
        FROM public.identity_tokens t
        WHERE t.token_digest = p_token_digest
          AND t.purpose = 'password_reset'
          AND t.consumed_at IS NULL
          AND t.expires_at > CURRENT_TIMESTAMP
        FOR UPDATE;

        IF v_token_id IS NULL THEN
          RETURN false;
        END IF;

        UPDATE public.users
        SET password_digest = p_password_digest,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = v_user_id;

        UPDATE public.identity_tokens
        SET consumed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
        WHERE id = v_token_id;

        UPDATE public.sessions
        SET revoked_at = COALESCE(revoked_at, CURRENT_TIMESTAMP),
            updated_at = CURRENT_TIMESTAMP
        WHERE user_id = v_user_id
          AND revoked_at IS NULL;

        RETURN true;
      END
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION crystell.issue_identity_token(text,text,text,timestamp without time zone) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.issue_identity_token(text,text,text,timestamp without time zone) TO crystell_runtime"
    execute "REVOKE ALL ON FUNCTION crystell.consume_email_verification(text) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.consume_email_verification(text) TO crystell_runtime"
    execute "REVOKE ALL ON FUNCTION crystell.consume_password_reset(text,text) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.consume_password_reset(text,text) TO crystell_runtime"
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.consume_password_reset(text,text)"
    execute "DROP FUNCTION IF EXISTS crystell.consume_email_verification(text)"
    execute "DROP FUNCTION IF EXISTS crystell.issue_identity_token(text,text,text,timestamp without time zone)"
    execute "DROP POLICY IF EXISTS migration_admin_access ON identity_tokens"
    execute "ALTER TABLE identity_tokens NO FORCE ROW LEVEL SECURITY"
    execute "ALTER TABLE identity_tokens DISABLE ROW LEVEL SECURITY"
  end
end
