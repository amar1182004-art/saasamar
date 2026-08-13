module Dashboard
  class Summary
    class MissingTenantContextError < StandardError; end

    def self.call(store_id:)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?
      TenantPermission.require!(Current.membership, "dashboard.read")

      store = Store.find(store_id)
      orders = Order.where(store_id: store.id)
      products = Product.where(store_id: store.id)
      inventory_levels = InventoryLevel.where(store_id: store.id)
      shipments = Shipment.where(store_id: store.id)

      {
        store: {
          id: store.id,
          name: store.name,
          status: store.status
        },
        orders: {
          total: orders.count,
          pending: orders.where(status: "pending").count,
          confirmed: orders.where(status: "confirmed").count,
          unpaid: orders.where(payment_status: "unpaid").count,
          paid: orders.where(payment_status: "paid").count,
          paid_order_value_by_currency: paid_order_value_by_currency(orders)
        },
        products: {
          total: products.count,
          active: products.where(status: "active").count,
          draft: products.where(status: "draft").count,
          archived: products.where(status: "archived").count
        },
        inventory: {
          out_of_stock_levels: inventory_levels.where("on_hand - reserved <= 0").count,
          reserved_units: inventory_levels.sum(:reserved),
          on_hand_units: inventory_levels.sum(:on_hand)
        },
        shipments: {
          total: shipments.count,
          label_ready: shipments.where(status: "label_ready").count,
          in_transit: shipments.where(status: "in_transit").count,
          delivered: shipments.where(status: "delivered").count,
          failed: shipments.where(status: "failed").count
        },
        recent_orders: recent_orders(orders)
      }
    end

    def self.paid_order_value_by_currency(orders)
      orders.where(payment_status: "paid")
            .group(:currency)
            .sum(:total_cents)
            .transform_values(&:to_i)
    end
    private_class_method :paid_order_value_by_currency

    def self.recent_orders(orders)
      orders.order(created_at: :desc, id: :desc).limit(5).map do |order|
        {
          id: order.id,
          order_number: order.order_number,
          status: order.status,
          payment_status: order.payment_status,
          fulfillment_status: order.fulfillment_status,
          total_cents: order.total_cents,
          currency: order.currency,
          created_at: order.created_at
        }
      end
    end
    private_class_method :recent_orders
  end
end
