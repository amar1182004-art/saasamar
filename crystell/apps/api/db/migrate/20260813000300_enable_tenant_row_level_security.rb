class EnableTenantRowLevelSecurity < ActiveRecord::Migration[8.0]
  TENANT_TABLES = {
    tenants: "id",
    memberships: "tenant_id",
    stores: "tenant_id"
  }.freeze

  def up
    execute "CREATE SCHEMA IF NOT EXISTS crystell"
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.current_tenant_id()
      RETURNS uuid
      LANGUAGE sql
      STABLE
      AS $$
        SELECT NULLIF(current_setting('app.current_tenant_id', true), '')::uuid
      $$
    SQL

    execute "GRANT USAGE ON SCHEMA crystell TO crystell_runtime"
    execute "GRANT EXECUTE ON FUNCTION crystell.current_tenant_id() TO crystell_runtime"

    TENANT_TABLES.each do |table, tenant_column|
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"

      execute <<~SQL
        CREATE POLICY tenant_runtime_isolation ON #{table}
        FOR ALL
        TO crystell_runtime
        USING (#{tenant_column} = crystell.current_tenant_id())
        WITH CHECK (#{tenant_column} = crystell.current_tenant_id())
      SQL

      execute <<~SQL
        DO $$
        BEGIN
          EXECUTE format(
            'CREATE POLICY migration_admin_access ON #{table} FOR ALL TO %I USING (true) WITH CHECK (true)',
            current_user
          );
        END
        $$
      SQL
    end
  end

  def down
    TENANT_TABLES.each_key do |table|
      execute "DROP POLICY IF EXISTS tenant_runtime_isolation ON #{table}"
      execute "DROP POLICY IF EXISTS migration_admin_access ON #{table}"
      execute "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
      execute "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
    end

    execute "DROP FUNCTION IF EXISTS crystell.current_tenant_id()"
  end
end
