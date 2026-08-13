class CreateControlPlaneCapabilitySchema < ActiveRecord::Migration[8.0]
  def up
    execute "CREATE SCHEMA IF NOT EXISTS control_plane_api"
    execute "REVOKE ALL ON SCHEMA control_plane_api FROM PUBLIC"
    execute "GRANT USAGE ON SCHEMA control_plane_api TO crystell_control_plane_runtime"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION control_plane_api.tenant_directory(
        p_query text,
        p_limit integer,
        p_offset integer
      )
      RETURNS TABLE(
        tenant_id uuid,
        tenant_name text,
        tenant_slug text,
        tenant_status text,
        stores_count bigint,
        active_stores_count bigint,
        created_at timestamp without time zone
      )
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = public, pg_temp
      AS $$
        SELECT tenant.id,
               tenant.name::text,
               tenant.slug::text,
               tenant.status::text,
               COUNT(store.id)::bigint,
               COUNT(store.id) FILTER (WHERE store.status = 'active')::bigint,
               tenant.created_at
        FROM tenants tenant
        LEFT JOIN stores store ON store.tenant_id = tenant.id
        WHERE NULLIF(BTRIM(p_query), '') IS NULL
           OR tenant.name ILIKE '%' || BTRIM(p_query) || '%'
           OR tenant.slug ILIKE '%' || BTRIM(p_query) || '%'
        GROUP BY tenant.id, tenant.name, tenant.slug, tenant.status, tenant.created_at
        ORDER BY tenant.created_at DESC, tenant.id
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100)
        OFFSET GREATEST(COALESCE(p_offset, 0), 0)
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION control_plane_api.tenant_directory(text, integer, integer) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION control_plane_api.tenant_directory(text, integer, integer) TO crystell_control_plane_runtime"
  end

  def down
    execute "DROP FUNCTION IF EXISTS control_plane_api.tenant_directory(text, integer, integer)"
    execute "DROP SCHEMA IF EXISTS control_plane_api"
  end
end
