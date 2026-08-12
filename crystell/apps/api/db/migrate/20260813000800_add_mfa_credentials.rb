class AddMfaCredentials < ActiveRecord::Migration[8.0]
  def up
    create_table :mfa_credentials, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true, index: { unique: true }
      t.text :encrypted_secret, null: false
      t.jsonb :recovery_code_digests, null: false, default: []
      t.datetime :confirmed_at
      t.datetime :last_used_at
      t.timestamps
    end

    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON mfa_credentials TO crystell_runtime"
    execute "ALTER TABLE mfa_credentials ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE mfa_credentials FORCE ROW LEVEL SECURITY"

    execute <<~SQL
      CREATE POLICY mfa_self_access ON mfa_credentials
      FOR ALL
      TO crystell_runtime
      USING (user_id = crystell.current_user_id())
      WITH CHECK (user_id = crystell.current_user_id())
    SQL

    execute <<~SQL
      DO $$
      BEGIN
        EXECUTE format(
          'CREATE POLICY migration_admin_access ON mfa_credentials FOR ALL TO %I USING (true) WITH CHECK (true)',
          current_user
        );
      END
      $$
    SQL
  end

  def down
    execute "DROP POLICY IF EXISTS migration_admin_access ON mfa_credentials"
    execute "DROP POLICY IF EXISTS mfa_self_access ON mfa_credentials"
    execute "ALTER TABLE mfa_credentials NO FORCE ROW LEVEL SECURITY"
    execute "ALTER TABLE mfa_credentials DISABLE ROW LEVEL SECURITY"
    execute "REVOKE SELECT, INSERT, UPDATE, DELETE ON mfa_credentials FROM crystell_runtime"
    drop_table :mfa_credentials
  end
end
