class GrantRuntimePrivileges < ActiveRecord::Migration[8.0]
  TENANT_TABLES = %w[tenants memberships stores].freeze

  def up
    execute "GRANT USAGE ON SCHEMA public TO crystell_runtime"

    TENANT_TABLES.each do |table|
      execute "GRANT SELECT, INSERT, UPDATE, DELETE ON #{table} TO crystell_runtime"
    end

    execute "GRANT SELECT, UPDATE ON users TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON sessions TO crystell_runtime"
  end

  def down
    execute "REVOKE SELECT, INSERT, UPDATE, DELETE ON sessions FROM crystell_runtime"
    execute "REVOKE SELECT, UPDATE ON users FROM crystell_runtime"

    TENANT_TABLES.each do |table|
      execute "REVOKE SELECT, INSERT, UPDATE, DELETE ON #{table} FROM crystell_runtime"
    end
  end
end
