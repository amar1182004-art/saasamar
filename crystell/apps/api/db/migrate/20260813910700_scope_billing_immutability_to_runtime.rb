class ScopeBillingImmutabilityToRuntime < ActiveRecord::Migration[8.0]
  def up
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

  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_billing_event_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'billing_events are append-only';
      END;
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_billing_append_only_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION '% is append-only', TG_TABLE_NAME;
      END;
      $$
    SQL
  end
end
