class AddBillingUuidDefaults < ActiveRecord::Migration[8.0]
  TABLES = %w[
    billing_plans
    billing_prices
    billing_features
    billing_entitlements
    subscriptions
    invoices
    usage_events
    usage_totals
    billing_events
  ].freeze

  def up
    TABLES.each do |table|
      execute "ALTER TABLE #{table} ALTER COLUMN id SET DEFAULT gen_random_uuid()"
    end
  end

  def down
    TABLES.each do |table|
      execute "ALTER TABLE #{table} ALTER COLUMN id DROP DEFAULT"
    end
  end
end
