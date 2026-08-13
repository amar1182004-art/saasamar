class CreateProductMedia < ActiveRecord::Migration[8.0]
  def up
    create_table :product_media, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :product_id, null: false
      t.uuid :product_variant_id
      t.string :media_type, null: false
      t.string :object_key, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :checksum_sha256
      t.string :alt_text
      t.integer :position, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.integer :width
      t.integer :height
      t.bigint :duration_ms
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_foreign_key :product_media, :tenants
    add_index :product_media, [:id, :tenant_id, :store_id], unique: true, name: "idx_product_media_id_tenant_store"
    add_index :product_media, [:tenant_id, :store_id, :product_id, :position], name: "idx_product_media_product_position"
    add_index :product_media, [:tenant_id, :object_key], unique: true, name: "idx_product_media_tenant_object_key"
    add_check_constraint :product_media, "media_type IN ('image', 'video')", name: "product_media_type_check"
    add_check_constraint :product_media, "status IN ('pending', 'ready', 'failed')", name: "product_media_status_check"
    add_check_constraint :product_media, "byte_size > 0", name: "product_media_byte_size_check"
    add_check_constraint :product_media, "position >= 0", name: "product_media_position_check"
    add_check_constraint :product_media, "width IS NULL OR width > 0", name: "product_media_width_check"
    add_check_constraint :product_media, "height IS NULL OR height > 0", name: "product_media_height_check"
    add_check_constraint :product_media, "duration_ms IS NULL OR duration_ms >= 0", name: "product_media_duration_check"

    execute "ALTER TABLE product_media ADD CONSTRAINT product_media_product_scope_fk FOREIGN KEY (product_id, tenant_id, store_id) REFERENCES products(id, tenant_id, store_id)"
    execute "ALTER TABLE product_media ADD CONSTRAINT product_media_variant_scope_fk FOREIGN KEY (product_variant_id, tenant_id, store_id) REFERENCES product_variants(id, tenant_id, store_id)"

    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON product_media TO crystell_runtime"
    execute "ALTER TABLE product_media ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE product_media FORCE ROW LEVEL SECURITY"
    execute <<~SQL
      CREATE POLICY tenant_runtime_isolation ON product_media
      FOR ALL
      TO crystell_runtime
      USING (tenant_id = crystell.current_tenant_id())
      WITH CHECK (tenant_id = crystell.current_tenant_id())
    SQL
    execute <<~SQL
      DO $$
      BEGIN
        EXECUTE format(
          'CREATE POLICY migration_admin_access ON product_media FOR ALL TO %I USING (true) WITH CHECK (true)',
          current_user
        );
      END
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.protect_product_media_identity()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.current_role_is_runtime() AND (
          NEW.tenant_id IS DISTINCT FROM OLD.tenant_id OR
          NEW.store_id IS DISTINCT FROM OLD.store_id OR
          NEW.product_id IS DISTINCT FROM OLD.product_id OR
          NEW.product_variant_id IS DISTINCT FROM OLD.product_variant_id OR
          NEW.object_key IS DISTINCT FROM OLD.object_key OR
          NEW.media_type IS DISTINCT FROM OLD.media_type
        ) THEN
          RAISE EXCEPTION 'product media identity fields are immutable for runtime roles';
        END IF;

        RETURN NEW;
      END;
      $$
    SQL
    execute <<~SQL
      CREATE TRIGGER product_media_protect_identity
      BEFORE UPDATE ON product_media
      FOR EACH ROW EXECUTE FUNCTION crystell.protect_product_media_identity()
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS product_media_protect_identity ON product_media"
    execute "DROP FUNCTION IF EXISTS crystell.protect_product_media_identity()"
    drop_table :product_media
  end
end
