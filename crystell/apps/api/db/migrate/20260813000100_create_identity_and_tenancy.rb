class CreateIdentityAndTenancy < ActiveRecord::Migration[8.0]
  def change
    enable_extension "citext" unless extension_enabled?("citext")

    create_table :users, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.citext :email, null: false
      t.string :password_digest
      t.string :status, null: false, default: "active"
      t.boolean :mfa_enabled, null: false, default: false
      t.datetime :last_signed_in_at
      t.timestamps
    end
    add_index :users, :email, unique: true
    add_check_constraint :users, "status IN ('active','invited','suspended')", name: "users_status_check"

    create_table :tenants, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.citext :slug, null: false
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :tenants, :slug, unique: true
    add_check_constraint :tenants, "status IN ('active','suspended','closed')", name: "tenants_status_check"

    create_table :memberships, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :tenant, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.string :role, null: false, default: "member"
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :memberships, %i[tenant_id user_id], unique: true
    add_check_constraint :memberships, "role IN ('owner','admin','member')", name: "memberships_role_check"
    add_check_constraint :memberships, "status IN ('active','invited','suspended')", name: "memberships_status_check"

    create_table :stores, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :tenant, null: false, type: :uuid, foreign_key: true
      t.string :name, null: false
      t.citext :slug, null: false
      t.string :status, null: false, default: "draft"
      t.timestamps
    end
    add_index :stores, %i[tenant_id slug], unique: true
    add_check_constraint :stores, "status IN ('draft','active','suspended','closed')", name: "stores_status_check"

    create_table :sessions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.string :ip_hash
      t.string :user_agent, limit: 512
      t.timestamps
    end
    add_index :sessions, :token_digest, unique: true
    add_index :sessions, %i[user_id revoked_at expires_at], name: "index_sessions_on_user_and_state"
  end
end
