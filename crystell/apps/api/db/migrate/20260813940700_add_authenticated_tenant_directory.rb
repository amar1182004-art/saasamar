class AddAuthenticatedTenantDirectory < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.current_user_tenants()
      RETURNS TABLE(
        tenant_id uuid,
        tenant_name text,
        tenant_slug text,
        tenant_status text,
        membership_role text,
        membership_status text,
        stores_count bigint
      )
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
        SELECT tenant.id,
               tenant.name::text,
               tenant.slug::text,
               tenant.status::text,
               membership.role::text,
               membership.status::text,
               COUNT(store.id)::bigint
        FROM public.memberships membership
        JOIN public.tenants tenant ON tenant.id = membership.tenant_id
        LEFT JOIN public.stores store ON store.tenant_id = tenant.id
        WHERE membership.user_id = crystell.current_user_id()
        GROUP BY tenant.id,
                 tenant.name,
                 tenant.slug,
                 tenant.status,
                 membership.role,
                 membership.status,
                 membership.created_at
        ORDER BY membership.created_at ASC, tenant.id ASC
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION crystell.current_user_tenants() FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.current_user_tenants() TO crystell_runtime"
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.current_user_tenants()"
  end
end
