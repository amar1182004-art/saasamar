class AddAtomicOwnershipTransfer < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.transfer_tenant_ownership(p_target_membership_id uuid)
      RETURNS uuid
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
      DECLARE
        v_user_id uuid := crystell.current_user_id();
        v_tenant_id uuid := crystell.current_tenant_id();
        v_current_owner_id uuid;
        v_target_user_id uuid;
      BEGIN
        IF v_user_id IS NULL OR v_tenant_id IS NULL THEN
          RAISE EXCEPTION 'identity and tenant context are required';
        END IF;

        SELECT m.id INTO v_current_owner_id
        FROM public.memberships m
        WHERE m.tenant_id = v_tenant_id
          AND m.user_id = v_user_id
          AND m.role = 'owner'
          AND m.status = 'active'
        FOR UPDATE;

        IF v_current_owner_id IS NULL THEN
          RAISE EXCEPTION 'current user is not the active tenant owner';
        END IF;

        SELECT m.user_id INTO v_target_user_id
        FROM public.memberships m
        JOIN public.users u ON u.id = m.user_id
        WHERE m.id = p_target_membership_id
          AND m.tenant_id = v_tenant_id
          AND m.status = 'active'
          AND u.status = 'active'
        FOR UPDATE OF m;

        IF v_target_user_id IS NULL OR v_target_user_id = v_user_id THEN
          RAISE EXCEPTION 'invalid ownership transfer target';
        END IF;

        UPDATE public.memberships
        SET role = 'admin', updated_at = CURRENT_TIMESTAMP
        WHERE id = v_current_owner_id;

        UPDATE public.memberships
        SET role = 'owner', updated_at = CURRENT_TIMESTAMP
        WHERE id = p_target_membership_id;

        RETURN v_target_user_id;
      END
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION crystell.transfer_tenant_ownership(uuid) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.transfer_tenant_ownership(uuid) TO crystell_runtime"
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.transfer_tenant_ownership(uuid)"
  end
end
