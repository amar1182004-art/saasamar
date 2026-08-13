class AdjustBillingLifecyclePrivileges < ActiveRecord::Migration[8.0]
  def up
    execute "DROP TRIGGER IF EXISTS billing_commissions_append_only ON billing_commissions"
    execute "GRANT UPDATE ON billing_affiliate_attributions TO crystell_runtime"
    execute "REVOKE UPDATE, DELETE ON billing_commissions FROM crystell_runtime"
  end

  def down
    execute "REVOKE UPDATE ON billing_affiliate_attributions FROM crystell_runtime"
    execute <<~SQL
      CREATE TRIGGER billing_commissions_append_only
      BEFORE UPDATE OR DELETE ON billing_commissions
      FOR EACH ROW EXECUTE FUNCTION crystell.prevent_billing_append_only_mutation()
    SQL
  end
end
