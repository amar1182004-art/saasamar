module Checkout
  class OrderPlacer
    class MissingTenantContextError < StandardError; end
    class InvalidCheckoutError < StandardError; end
    class InconsistentReservationError < StandardError; end

    def self.call(checkout_session_id:, now: Time.current)
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?

      order = nil
      ApplicationRecord.transaction(requires_new: true) do
        checkout = CheckoutSession.lock.find(checkout_session_id)
        existing = Order.find_by(checkout_session_id: checkout.id)
        if existing
          order = existing
          next
        end

        raise InvalidCheckoutError, "checkout has expired" if checkout.expires_at <= now
        raise InvalidCheckoutError, "checkout inventory must be reserved before order placement" unless checkout.status == "inventory_reserved"

        reservation_ids = CheckoutInventoryReservation.where(checkout_session_id: checkout.id)
                                                      .pluck(:inventory_reservation_id)
        if reservation_ids.any?
          active_count = InventoryReservation.active.where(id: reservation_ids).count
          raise InconsistentReservationError, "checkout inventory reservations are not active" unless active_count == reservation_ids.length
        end

        order_number = next_order_number!(checkout.store_id)
        order = Order.create!(
          tenant_id: Current.tenant_id,
          store_id: checkout.store_id,
          checkout_session_id: checkout.id,
          order_number: order_number,
          status: "pending",
          payment_status: "unpaid",
          fulfillment_status: "unfulfilled",
          currency: checkout.currency,
          subtotal_cents: checkout.subtotal_cents,
          discount_cents: checkout.discount_cents,
          shipping_cents: checkout.shipping_cents,
          tax_cents: checkout.tax_cents,
          total_cents: checkout.total_cents,
          customer_email: checkout.customer_email,
          shipping_address: checkout.shipping_address,
          billing_address: checkout.billing_address,
          placed_at: now,
          metadata: {}
        )

        CheckoutLineItem.where(checkout_session_id: checkout.id).order(:created_at, :id).find_each do |line|
          OrderItem.create!(
            tenant_id: Current.tenant_id,
            store_id: checkout.store_id,
            order_id: order.id,
            product_id: line.product_id,
            product_variant_id: line.product_variant_id,
            product_title: line.product_title,
            variant_title: line.variant_title,
            sku: line.sku,
            currency: line.currency,
            unit_price_cents: line.unit_price_cents,
            quantity: line.quantity,
            line_subtotal_cents: line.line_subtotal_cents,
            taxable: line.taxable,
            option_values: line.option_values,
            metadata: line.metadata
          )
        end

        checkout.update!(status: "payment_pending")
      end

      order
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.match?(/orders.*checkout|idx_orders_checkout_unique/i)

      Order.find_by!(checkout_session_id: checkout_session_id)
    end

    def self.next_order_number!(store_id)
      connection = ApplicationRecord.connection
      sql = "SELECT crystell.next_store_order_number(#{connection.quote(store_id)}::uuid)"
      Integer(connection.select_value(sql))
    end
    private_class_method :next_order_number!
  end
end
