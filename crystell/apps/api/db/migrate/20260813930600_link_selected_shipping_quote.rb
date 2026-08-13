class LinkSelectedShippingQuote < ActiveRecord::Migration[8.0]
  def up
    add_column :checkout_sessions, :selected_shipping_rate_quote_id, :uuid
    add_index :checkout_sessions, [:tenant_id, :store_id, :selected_shipping_rate_quote_id], name: "idx_checkout_selected_shipping_quote"
    execute <<~SQL
      ALTER TABLE checkout_sessions
      ADD CONSTRAINT checkout_selected_shipping_quote_scope_fk
      FOREIGN KEY (selected_shipping_rate_quote_id, tenant_id, store_id)
      REFERENCES shipping_rate_quotes(id, tenant_id, store_id)
      DEFERRABLE INITIALLY DEFERRED
    SQL
  end

  def down
    execute "ALTER TABLE checkout_sessions DROP CONSTRAINT IF EXISTS checkout_selected_shipping_quote_scope_fk"
    remove_column :checkout_sessions, :selected_shipping_rate_quote_id
  end
end
