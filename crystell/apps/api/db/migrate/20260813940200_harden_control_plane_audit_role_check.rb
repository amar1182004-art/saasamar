class HardenControlPlaneAuditRoleCheck < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_control_plane_audit_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        runtime_member boolean;
      BEGIN
        SELECT EXISTS (
          SELECT 1
          FROM pg_auth_members membership
          JOIN pg_roles role ON role.oid = membership.roleid
          JOIN pg_roles member ON member.oid = membership.member
          WHERE role.rolname = 'crystell_control_plane_runtime'
            AND member.rolname = current_user
        ) INTO runtime_member;

        IF runtime_member THEN
          RAISE EXCEPTION 'control_plane_audit_events_are_append_only';
        END IF;

        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;

        RETURN NEW;
      END;
      $$
    SQL
  end

  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_control_plane_audit_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.current_role_is_control_plane_runtime() THEN
          RAISE EXCEPTION 'control_plane_audit_events_are_append_only';
        END IF;

        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;

        RETURN NEW;
      END;
      $$
    SQL
  end
end
