class AddTenantInvitationsAndOwnerIntegrity < ActiveRecord::Migration[8.0]
  def up
    add_index :memberships,
      :tenant_id,
      unique: true,
      where: "role = 'owner' AND status = 'active'",
      name: "index_memberships_on_single_active_owner"

    create_table :tenant_invitations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :tenant, null: false, type: :uuid, foreign_key: true
      t.uuid :invited_by_user_id, null: false
      t.citext :email, null: false
      t.string :role, null: false, default: "member"
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_foreign_key :tenant_invitations, :users, column: :invited_by_user_id
    add_index :tenant_invitations, :token_digest, unique: true
    add_index :tenant_invitations,
      %i[tenant_id email],
      unique: true,
      where: "accepted_at IS NULL AND revoked_at IS NULL",
      name: "index_active_tenant_invitation_per_email"
    add_check_constraint :tenant_invitations,
      "role IN ('admin','member')",
      name: "tenant_invitations_role_check"

    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON tenant_invitations TO crystell_runtime"
    execute "ALTER TABLE tenant_invitations ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE tenant_invitations FORCE ROW LEVEL SECURITY"

    execute <<~SQL
      CREATE POLICY tenant_invitation_runtime_isolation ON tenant_invitations
      FOR ALL
      TO crystell_runtime
      USING (tenant_id = crystell.current_tenant_id())
      WITH CHECK (tenant_id = crystell.current_tenant_id())
    SQL

    execute <<~SQL
      DO $$
      BEGIN
        EXECUTE format(
          'CREATE POLICY migration_admin_access ON tenant_invitations FOR ALL TO %I USING (true) WITH CHECK (true)',
          current_user
        );
      END
      $$
    SQL

    remove_check_constraint :identity_delivery_outbox, name: "identity_delivery_outbox_purpose_check"
    add_check_constraint :identity_delivery_outbox,
      "purpose IN ('email_verification','password_reset','tenant_invitation')",
      name: "identity_delivery_outbox_purpose_check"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.enqueue_tenant_invitation_delivery(
        p_destination_fingerprint text,
        p_encrypted_payload text
      )
      RETURNS uuid
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
      DECLARE
        v_outbox_id uuid := gen_random_uuid();
      BEGIN
        INSERT INTO public.identity_delivery_outbox (
          id,
          purpose,
          destination_fingerprint,
          encrypted_payload,
          available_at,
          created_at,
          updated_at
        ) VALUES (
          v_outbox_id,
          'tenant_invitation',
          p_destination_fingerprint,
          p_encrypted_payload,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        );

        RETURN v_outbox_id;
      END
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.accept_tenant_invitation(
        p_token_digest text,
        p_user_id uuid
      )
      RETURNS uuid
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
      DECLARE
        v_invitation public.tenant_invitations%ROWTYPE;
        v_user_email public.citext;
      BEGIN
        SELECT * INTO v_invitation
        FROM public.tenant_invitations
        WHERE token_digest = p_token_digest
          AND accepted_at IS NULL
          AND revoked_at IS NULL
          AND expires_at > CURRENT_TIMESTAMP
        FOR UPDATE;

        IF v_invitation.id IS NULL THEN
          RETURN NULL;
        END IF;

        SELECT email INTO v_user_email
        FROM public.users
        WHERE id = p_user_id
          AND status = 'active';

        IF v_user_email IS NULL OR v_user_email <> v_invitation.email THEN
          RETURN NULL;
        END IF;

        INSERT INTO public.memberships (
          id, tenant_id, user_id, role, status, created_at, updated_at
        ) VALUES (
          gen_random_uuid(),
          v_invitation.tenant_id,
          p_user_id,
          v_invitation.role,
          'active',
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        )
        ON CONFLICT (tenant_id, user_id) DO UPDATE
        SET role = EXCLUDED.role,
            status = 'active',
            updated_at = CURRENT_TIMESTAMP;

        UPDATE public.tenant_invitations
        SET accepted_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = v_invitation.id;

        RETURN v_invitation.tenant_id;
      END
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION crystell.enqueue_tenant_invitation_delivery(text,text) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.enqueue_tenant_invitation_delivery(text,text) TO crystell_runtime"
    execute "REVOKE ALL ON FUNCTION crystell.accept_tenant_invitation(text,uuid) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.accept_tenant_invitation(text,uuid) TO crystell_runtime"
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.accept_tenant_invitation(text,uuid)"
    execute "DROP FUNCTION IF EXISTS crystell.enqueue_tenant_invitation_delivery(text,text)"

    remove_check_constraint :identity_delivery_outbox, name: "identity_delivery_outbox_purpose_check"
    add_check_constraint :identity_delivery_outbox,
      "purpose IN ('email_verification','password_reset')",
      name: "identity_delivery_outbox_purpose_check"

    execute "DROP POLICY IF EXISTS migration_admin_access ON tenant_invitations"
    execute "DROP POLICY IF EXISTS tenant_invitation_runtime_isolation ON tenant_invitations"
    execute "ALTER TABLE tenant_invitations NO FORCE ROW LEVEL SECURITY"
    execute "ALTER TABLE tenant_invitations DISABLE ROW LEVEL SECURITY"
    execute "REVOKE SELECT, INSERT, UPDATE, DELETE ON tenant_invitations FROM crystell_runtime"

    drop_table :tenant_invitations
    remove_index :memberships, name: "index_memberships_on_single_active_owner"
  end
end
