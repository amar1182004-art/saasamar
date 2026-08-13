class AddInvoiceIdempotency < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :idempotency_key, :string
    add_index :invoices,
              [:tenant_id, :idempotency_key],
              unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "idx_invoices_tenant_idempotency"
  end
end
