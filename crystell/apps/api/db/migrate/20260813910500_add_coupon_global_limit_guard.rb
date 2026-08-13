class AddCouponGlobalLimitGuard < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.billing_coupon_globally_available(p_coupon_id uuid)
      RETURNS boolean
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
        SELECT EXISTS (
          SELECT 1
          FROM public.billing_coupons c
          WHERE c.id = p_coupon_id
            AND c.status = 'active'
            AND (c.starts_at IS NULL OR c.starts_at <= CURRENT_TIMESTAMP)
            AND (c.ends_at IS NULL OR c.ends_at > CURRENT_TIMESTAMP)
            AND (
              c.max_redemptions IS NULL OR
              (SELECT count(*) FROM public.billing_coupon_redemptions r WHERE r.billing_coupon_id = c.id) < c.max_redemptions
            )
        )
      $$
    SQL
    execute "REVOKE ALL ON FUNCTION crystell.billing_coupon_globally_available(uuid) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.billing_coupon_globally_available(uuid) TO crystell_runtime"
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.billing_coupon_globally_available(uuid)"
  end
end
