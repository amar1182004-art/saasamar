class AddControlPlaneTenantSupportOverview < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION control_plane_api.tenant_support_overview(p_tenant_id uuid)
      RETURNS TABLE(
        tenant_id uuid,
        tenant_name text,
        tenant_slug text,
        tenant_status text,
        stores_count bigint,
        active_stores_count bigint,
        orders_count bigint,
        paid_orders_count bigint,
        open_shipments_count bigint,
        products_count bigint,
        active_products_count bigint,
        subscription_status text,
        subscription_plan_code text,
        created_at timestamp without time zone
      )
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = public, pg_temp
      AS $$
        SELECT
          tenant.id,
          tenant.name::text,
          tenant.slug::text,
          tenant.status::text,
          (SELECT COUNT(*) FROM stores store WHERE store.tenant_id = tenant.id)::bigint,
          (SELECT COUNT(*) FROM stores store WHERE store.tenant_id = tenant.id AND store.status = 'active')::bigint,
          (SELECT COUNT(*) FROM orders customer_order WHERE customer_order.tenant_id = tenant.id)::bigint,
          (SELECT COUNT(*) FROM orders customer_order WHERE customer_order.tenant_id = tenant.id AND customer_order.payment_status = 'paid')::bigint,
          (SELECT COUNT(*) FROM shipments shipment WHERE shipment.tenant_id = tenant.id AND shipment.status IN ('pending', 'submitted', 'label_ready', 'in_transit'))::bigint,
          (SELECT COUNT(*) FROM products product WHERE product.tenant_id = tenant.id)::bigint,
          (SELECT COUNT(*) FROM products product WHERE product.tenant_id = tenant.id AND product.status = 'active')::bigint,
          subscription.status::text,
          plan.code::text,
          tenant.created_at
        FROM tenants tenant
        LEFT JOIN LATERAL (
          SELECT tenant_subscription.status, tenant_subscription.billing_plan_id
          FROM subscriptions tenant_subscription
          WHERE tenant_subscription.tenant_id = tenant.id
          ORDER BY tenant_subscription.created_at DESC, tenant_subscription.id DESC
          LIMIT 1
        ) subscription ON true
        LEFT JOIN billing_plans plan ON plan.id = subscription.billing_plan_id
        WHERE tenant.id = p_tenant_id
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION control_plane_api.tenant_support_overview(uuid) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION control_plane_api.tenant_support_overview(uuid) TO crystell_control_plane_runtime"
  end

  def down
    execute "DROP FUNCTION IF EXISTS control_plane_api.tenant_support_overview(uuid)"
  end
end
