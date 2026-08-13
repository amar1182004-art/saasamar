class CreateStorefrontConfigurations < ActiveRecord::Migration[8.0]
  def up
    create_table :storefront_configurations, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.string :status, null: false, default: "offline"
      t.jsonb :draft_config, null: false, default: {
        theme_key: "default",
        locale: "en",
        currency_code: "USD",
        settings: {}
      }
      t.jsonb :published_config, null: false, default: {
        theme_key: "default",
        locale: "en",
        currency_code: "USD",
        settings: {}
      }
      t.bigint :draft_version, null: false, default: 0
      t.bigint :published_version, null: false, default: 0
      t.datetime :published_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_foreign_key :storefront_configurations, :tenants
    add_index :storefront_configurations, [:tenant_id, :store_id], unique: true, name: "idx_storefront_config_tenant_store"
    add_check_constraint :storefront_configurations, "status IN ('offline', 'online')", name: "storefront_config_status_check"
    add_check_constraint :storefront_configurations, "jsonb_typeof(draft_config) = 'object'", name: "storefront_draft_config_object_check"
    add_check_constraint :storefront_configurations, "jsonb_typeof(published_config) = 'object'", name: "storefront_published_config_object_check"
    add_check_constraint :storefront_configurations, "draft_version >= 0", name: "storefront_draft_version_check"
    add_check_constraint :storefront_configurations, "published_version >= 0", name: "storefront_published_version_check"

    execute "ALTER TABLE storefront_configurations ADD CONSTRAINT storefront_config_store_tenant_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON storefront_configurations TO crystell_runtime"

    execute "ALTER TABLE storefront_configurations ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE storefront_configurations FORCE ROW LEVEL SECURITY"
    execute <<~SQL
      CREATE POLICY tenant_runtime_isolation ON storefront_configurations
      FOR ALL
      TO crystell_runtime
      USING (tenant_id = crystell.current_tenant_id())
      WITH CHECK (tenant_id = crystell.current_tenant_id())
    SQL
    execute <<~SQL
      DO $$
      BEGIN
        EXECUTE format(
          'CREATE POLICY migration_admin_access ON storefront_configurations FOR ALL TO %I USING (true) WITH CHECK (true)',
          current_user
        );
      END
      $$
    SQL
  end

  def down
    execute "DROP POLICY IF EXISTS tenant_runtime_isolation ON storefront_configurations"
    execute "DROP POLICY IF EXISTS migration_admin_access ON storefront_configurations"
    drop_table :storefront_configurations
  end
end
