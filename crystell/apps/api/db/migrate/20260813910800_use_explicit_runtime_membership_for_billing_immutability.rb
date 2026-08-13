class UseExplicitRuntimeMembershipForBillingImmutability < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.current_role_is_runtime()
      RETURNS boolean
      LANGUAGE sql
      STABLE
      AS $$
        SELECT
          current_user = 'crystell_runtime'
          OR EXISTS (
            SELECT 1
            FROM pg_auth_members membership
            JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
            JOIN pg_roles member_role ON member_role.oid = membership.member
            WHERE granted_role.rolname = 'crystell_runtime'
              AND member_role.rolname = current_user
          )
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_billing_event_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.current_role_is_runtime() THEN
          RAISE EXCEPTION 'billing_events are append-only for runtime roles';
        END IF;

        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;

        RETURN NEW;
      END;
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_billing_append_only_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.current_role_is_runtime() THEN
          RAISE EXCEPTION '% is append-only for runtime roles', TG_TABLE_NAME;
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
    execute "DROP FUNCTION IF EXISTS crystell.current_role_is_runtime()"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_billing_event_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF pg_has_role(current_user, 'crystell_runtime', 'MEMBER') THEN
          RAISE EXCEPTION 'billing_events are append-only for runtime roles';
        END IF;

        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;

        RETURN NEW;
      END;
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_billing_append_only_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF pg_has_role(current_user, 'crystell_runtime', 'MEMBER') THEN
          RAISE EXCEPTION '% is append-only for runtime roles', TG_TABLE_NAME;
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
