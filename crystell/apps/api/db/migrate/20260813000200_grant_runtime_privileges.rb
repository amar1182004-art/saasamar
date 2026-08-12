class GrantRuntimePrivileges < ActiveRecord::Migration[8.0]
  def up
    execute "GRANT USAGE ON SCHEMA public TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO crystell_runtime"
    execute "GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO crystell_runtime"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO crystell_runtime"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO crystell_runtime"
  end

  def down
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM crystell_runtime"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE USAGE, SELECT, UPDATE ON SEQUENCES FROM crystell_runtime"
    execute "REVOKE USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public FROM crystell_runtime"
    execute "REVOKE SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM crystell_runtime"
  end
end
