class EnforceSingleCurrentSubscription < ActiveRecord::Migration[8.0]
  def change
    add_index :subscriptions,
              :tenant_id,
              unique: true,
              where: "status IN ('trialing', 'active', 'past_due', 'paused')",
              name: "idx_subscriptions_one_current_per_tenant"
  end
end
