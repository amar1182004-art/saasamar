class ProtectShippingWebhookIdentity < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_shipping_webhook_identity_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.current_role_is_runtime() AND (
          NEW.tenant_id IS DISTINCT FROM OLD.tenant_id OR
          NEW.store_id IS DISTINCT FROM OLD.store_id OR
          NEW.shipping_provider_account_id IS DISTINCT FROM OLD.shipping_provider_account_id OR
          NEW.provider_event_id IS DISTINCT FROM OLD.provider_event_id OR
          NEW.event_type IS DISTINCT FROM OLD.event_type OR
          NEW.payload_digest IS DISTINCT FROM OLD.payload_digest OR
          NEW.signature_digest IS DISTINCT FROM OLD.signature_digest OR
          NEW.raw_body_ciphertext IS DISTINCT FROM OLD.raw_body_ciphertext OR
          NEW.received_at IS DISTINCT FROM OLD.received_at
        ) THEN
          RAISE EXCEPTION 'shipping_webhook_identity_is_immutable';
        END IF;

        RETURN NEW;
      END;
      $$
    SQL

    execute <<~SQL
      CREATE TRIGGER shipping_webhook_identity_immutable
      BEFORE UPDATE ON shipping_webhook_events
      FOR EACH ROW EXECUTE FUNCTION crystell.prevent_shipping_webhook_identity_mutation()
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS shipping_webhook_identity_immutable ON shipping_webhook_events"
    execute "DROP FUNCTION IF EXISTS crystell.prevent_shipping_webhook_identity_mutation()"
  end
end
