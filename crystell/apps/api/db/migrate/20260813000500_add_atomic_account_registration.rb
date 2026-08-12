class AddAtomicAccountRegistration < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.create_initial_account(
        p_email text,
        p_password_digest text,
        p_tenant_name text,
        p_tenant_slug text,
        p_store_name text,
        p_store_slug text
      )
      RETURNS TABLE(user_id uuid, tenant_id uuid, store_id uuid)
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
      DECLARE
        v_user_id uuid := gen_random_uuid();
        v_tenant_id uuid := gen_random_uuid();
        v_store_id uuid := gen_random_uuid();
      BEGIN
        INSERT INTO public.users (id, email, password_digest, status, created_at, updated_at)
        VALUES (v_user_id, p_email::public.citext, p_password_digest, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

        INSERT INTO public.tenants (id, name, slug, status, created_at, updated_at)
        VALUES (v_tenant_id, p_tenant_name, p_tenant_slug::public.citext, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

        INSERT INTO public.memberships (id, tenant_id, user_id, role, status, created_at, updated_at)
        VALUES (gen_random_uuid(), v_tenant_id, v_user_id, 'owner', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

        INSERT INTO public.stores (id, tenant_id, name, slug, status, created_at, updated_at)
        VALUES (v_store_id, v_tenant_id, p_store_name, p_store_slug::public.citext, 'draft', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

        RETURN QUERY SELECT v_user_id, v_tenant_id, v_store_id;
      END
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION crystell.create_initial_account(text, text, text, text, text, text) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.create_initial_account(text, text, text, text, text, text) TO crystell_runtime"
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.create_initial_account(text, text, text, text, text, text)"
  end
end
