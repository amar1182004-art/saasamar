class UseExplicitRuntimeMembershipForShippingImmutability < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_shipment_event_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.current_role_is_runtime() THEN
          RAISE EXCEPTION 'shipment_events_are_append_only';
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
      CREATE OR REPLACE FUNCTION crystell.prevent_shipment_event_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.is_runtime_role() THEN
          RAISE EXCEPTION 'shipment_events_are_append_only';
        END IF;

        RETURN OLD;
      END;
      $$
    SQL
  end
end
