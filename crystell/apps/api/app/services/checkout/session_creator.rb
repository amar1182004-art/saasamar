module Checkout
  class SessionCreator
    class MissingTenantContextError < StandardError; end
    class EmptyCartError < StandardError; end
    class InvalidCartError < StandardError; end
    class IdempotencyConflictError < StandardError; end

    DEFAULT_TTL = 30.minutes

    def self.call(store_id:, cart_access_token:, idempotency_key:, customer_email: nil, shipping_address: {}, billing_address: {})
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?
      raise InvalidCartError, "idempotency key is required" if idempotency_key.blank?

      cart_snapshot = Commerce::CartManager.read(store_id: store_id, access_token: cart_access_token)
      existing = CheckoutSession.find_by(tenant_id: Current.tenant_id, idempotency_key: idempotency_key)
      return verify_existing!(existing, store_id, cart_snapshot.id) if existing

      result = nil
      Commerce::CartManager.with_locked_active_cart(store_id: store_id, access_token: cart_access_token) do |cart|
        existing = CheckoutSession.find_by(tenant_id: Current.tenant_id, idempotency_key: idempotency_key)
        if existing
          result = verify_existing!(existing, cart.store_id, cart.id)
          next
        end

        items = CartItem.where(cart_id: cart.id).order(:created_at).to_a
        raise EmptyCartError, "cart must contain at least one item" if items.empty?
        raise InvalidCartError, "cart currency is missing" if cart.currency.blank?

        variant_ids = items.map(&:product_variant_id)
        variants = ProductVariant.where(id: variant_ids, store_id: cart.store_id, status: "active").includes(:product).index_by(&:id)
        raise InvalidCartError, "one or more cart variants are unavailable" unless variants.length == variant_ids.uniq.length

        line_snapshots = items.map do |item|
          variant = variants.fetch(item.product_variant_id)
          product = variant.product
          raise InvalidCartError, "one or more products are unavailable" unless product.status == "active" && product.published_at.present? && product.published_at <= Time.current
          raise InvalidCartError, "cart currency changed" unless variant.currency == cart.currency

          {
            product_id: product.id,
            product_variant_id: variant.id,
            product_title: product.title,
            variant_title: variant.title,
            sku: variant.sku,
            currency: variant.currency,
            unit_price_cents: variant.price_cents,
            quantity: item.quantity,
            line_subtotal_cents: variant.price_cents * item.quantity,
            taxable: variant.taxable,
            option_values: variant.option_values,
            metadata: {}
          }
        end

        subtotal = line_snapshots.sum { |line| line.fetch(:line_subtotal_cents) }
        now = Time.current
        session = CheckoutSession.create!(
          tenant_id: Current.tenant_id,
          store_id: cart.store_id,
          cart_id: cart.id,
          status: "open",
          currency: cart.currency,
          subtotal_cents: subtotal,
          discount_cents: 0,
          shipping_cents: 0,
          tax_cents: 0,
          total_cents: subtotal,
          customer_email: customer_email,
          shipping_address: normalize_object(shipping_address, "shipping_address"),
          billing_address: normalize_object(billing_address, "billing_address"),
          idempotency_key: idempotency_key,
          priced_at: now,
          expires_at: DEFAULT_TTL.from_now
        )

        line_snapshots.each do |attributes|
          CheckoutLineItem.create!(attributes.merge(
            tenant_id: Current.tenant_id,
            store_id: cart.store_id,
            checkout_session_id: session.id
          ))
        end
        cart.update!(status: "checking_out")
        result = session
      end

      result
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.match?(/checkout.*idempotency|idx_checkout_idempotency/i)

      cart = Commerce::CartManager.read(store_id: store_id, access_token: cart_access_token)
      existing = CheckoutSession.find_by!(tenant_id: Current.tenant_id, idempotency_key: idempotency_key)
      verify_existing!(existing, store_id, cart.id)
    end

    def self.verify_existing!(session, store_id, cart_id)
      same_request = session.store_id.to_s == store_id.to_s && session.cart_id.to_s == cart_id.to_s
      return session if same_request

      raise IdempotencyConflictError, "idempotency key was already used for another checkout"
    end
    private_class_method :verify_existing!

    def self.normalize_object(value, field)
      object = value.respond_to?(:to_h) ? value.to_h : nil
      raise InvalidCartError, "#{field} must be an object" unless object.is_a?(Hash)

      object
    end
    private_class_method :normalize_object
  end
end
