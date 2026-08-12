class AddEncryptedIdentityDeliveryOutbox < ActiveRecord::Migration[8.0]
  def up
    create_table :identity_delivery_outbox, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :purpose, null: false
      t.string :destination_fingerprint, null: false
      t.text :encrypted_payload, null: false
      t.datetime :available_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :claimed_at
      t.datetime :delivered_at
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.timestamps
    end

    add_index :identity_delivery_outbox, %i[delivered_at available_at], name: "index_identity_delivery_outbox_on_delivery_state"
    add_index :identity_delivery_outbox, %i[purpose destination_fingerprint created_at], name: "index_identity_delivery_outbox_on_destination"
    add_check_constraint :identity_delivery_outbox,
      "purpose IN ('email_verification','password_reset')",
      name: "identity_delivery_outbox_purpose_check"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.request_identity_delivery(
        p_email text,
        p_purpose text,
        p_token_digest text,
        p_expires_at timestamp without time zone,
        p_destination_fingerprint text,
        p_encrypted_payload text
      )
      RETURNS boolean
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
      DECLARE
        v_user_id uuid;
      BEGIN
        IF p_purpose NOT IN ('email_verification', 'password_reset') THEN
          RAISE EXCEPTION 'invalid identity delivery purpose';
        END IF;

        SELECT u.id INTO v_user_id
        FROM public.users u
        WHERE u.email = p_email::public.citext
          AND u.status = 'active'
        LIMIT 1;

        IF v_user_id IS NULL THEN
          RETURN false;
        END IF;

        UPDATE public.identity_tokens
        SET consumed_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        WHERE user_id = v_user_id
          AND purpose = p_purpose
          AND consumed_at IS NULL;

        INSERT INTO public.identity_tokens (
          id, user_id, purpose, token_digest, expires_at, created_at, updated_at
        ) VALUES (
          gen_random_uuid(),
          v_user_id,
          p_purpose,
          p_token_digest,
          p_expires_at,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        );

        INSERT INTO public.identity_delivery_outbox (
          id,
          purpose,
          destination_fingerprint,
          encrypted_payload,
          available_at,
          created_at,
          updated_at
        ) VALUES (
          gen_random_uuid(),
          p_purpose,
          p_destination_fingerprint,
          p_encrypted_payload,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        );

        RETURN true;
      END
      $$
    SQL

    execute "REVOKE ALL ON TABLE identity_delivery_outbox FROM crystell_runtime"
    execute "REVOKE ALL ON FUNCTION crystell.request_identity_delivery(text,text,text,timestamp without time zone,text,text) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.request_identity_delivery(text,text,text,timestamp without time zone,text,text) TO crystell_runtime"
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.request_identity_delivery(text,text,text,timestamp without time zone,text,text)"
    drop_table :identity_delivery_outbox
  end
end
