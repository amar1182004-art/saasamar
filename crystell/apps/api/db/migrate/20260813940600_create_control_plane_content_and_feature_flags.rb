class CreateControlPlaneContentAndFeatureFlags < ActiveRecord::Migration[8.0]
  CONTROL_TABLES = %w[
    control_plane_content_documents
    control_plane_content_versions
    control_plane_feature_flags
  ].freeze

  def up
    create_content_documents
    create_content_versions
    create_feature_flags
    configure_version_immutability
    configure_database_access
  end

  def down
    execute "DROP TRIGGER IF EXISTS control_plane_content_versions_append_only ON control_plane_content_versions"
    execute "DROP FUNCTION IF EXISTS crystell.prevent_control_plane_content_version_mutation()"

    drop_table :control_plane_feature_flags
    drop_table :control_plane_content_versions
    drop_table :control_plane_content_documents
  end

  private

  def create_content_documents
    create_table :control_plane_content_documents, id: :uuid do |t|
      t.string :key, null: false
      t.string :kind, null: false
      t.string :locale, null: false, default: "en"
      t.jsonb :draft_content, null: false, default: {}
      t.jsonb :published_content, null: false, default: {}
      t.integer :draft_version, null: false, default: 0
      t.integer :published_version, null: false, default: 0
      t.datetime :published_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :control_plane_content_documents,
              [:key, :locale],
              unique: true,
              name: "idx_control_plane_content_key_locale"
    add_index :control_plane_content_documents,
              [:kind, :locale],
              name: "idx_control_plane_content_kind_locale"
    add_check_constraint :control_plane_content_documents,
                         "kind IN ('branding', 'page', 'navigation', 'footer', 'banner', 'ad')",
                         name: "control_plane_content_kind_check"
    add_check_constraint :control_plane_content_documents,
                         "draft_version >= 0 AND published_version >= 0 AND published_version <= draft_version",
                         name: "control_plane_content_version_check"
  end

  def create_content_versions
    create_table :control_plane_content_versions, id: :uuid do |t|
      t.uuid :control_plane_content_document_id, null: false
      t.uuid :control_plane_user_id, null: false
      t.integer :version, null: false
      t.string :source, null: false, default: "draft"
      t.jsonb :content, null: false, default: {}
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_foreign_key :control_plane_content_versions, :control_plane_content_documents
    add_foreign_key :control_plane_content_versions, :control_plane_users
    add_index :control_plane_content_versions,
              [:control_plane_content_document_id, :version],
              unique: true,
              name: "idx_control_plane_content_versions_document_version"
    add_check_constraint :control_plane_content_versions,
                         "version > 0",
                         name: "control_plane_content_versions_positive_check"
    add_check_constraint :control_plane_content_versions,
                         "source IN ('draft', 'rollback')",
                         name: "control_plane_content_versions_source_check"
  end

  def create_feature_flags
    create_table :control_plane_feature_flags, id: :uuid do |t|
      t.string :key, null: false
      t.text :description
      t.boolean :enabled, null: false, default: false
      t.integer :rollout_percentage, null: false, default: 0
      t.jsonb :config, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :control_plane_feature_flags, :key, unique: true
    add_check_constraint :control_plane_feature_flags,
                         "rollout_percentage BETWEEN 0 AND 100",
                         name: "control_plane_feature_flags_rollout_check"
  end

  def configure_version_immutability
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_control_plane_content_version_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.current_role_is_control_plane_runtime() THEN
          RAISE EXCEPTION 'control_plane_content_versions_are_append_only';
        END IF;

        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;

        RETURN NEW;
      END;
      $$
    SQL

    execute <<~SQL
      CREATE TRIGGER control_plane_content_versions_append_only
      BEFORE UPDATE OR DELETE ON control_plane_content_versions
      FOR EACH ROW EXECUTE FUNCTION crystell.prevent_control_plane_content_version_mutation()
    SQL
  end

  def configure_database_access
    CONTROL_TABLES.each do |table|
      execute "REVOKE ALL ON #{table} FROM crystell_runtime"
    end

    execute "GRANT SELECT, INSERT, UPDATE ON control_plane_content_documents TO crystell_control_plane_runtime"
    execute "GRANT SELECT, INSERT ON control_plane_content_versions TO crystell_control_plane_runtime"
    execute "GRANT SELECT, INSERT, UPDATE ON control_plane_feature_flags TO crystell_control_plane_runtime"
  end
end
