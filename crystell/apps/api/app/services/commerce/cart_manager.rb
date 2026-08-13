require "digest"
require "securerandom"

module Commerce
  class CartManager
    class MissingTenantContextError < StandardError; end
    class InvalidCartError < StandardError; end
    class InvalidItemError < StandardError; end
    class CurrencyMismatchError < StandardError; end

    Created = Data.define(:cart, :access_token)

    DEFAULT_TTL = 14.days

    def self.create(store_id:, expires_at: nil)
      require_tenant!
      store = Store.find_by!(id: store_id, status: "active")
      raw_token = SecureRandom.urlsafe_base64(32)
      cart = Cart.create!(
        tenant_id: Current.tenant_id,
        store_id: store.id,
        access_token_digest: digest(raw_token),
        status: "active",
        expires_at: expires_at || DEFAULT_TTL.from_now
      )

      Created.new(cart: cart, access_token: raw_token)
    end

    def self.add_item(store_id:, access_token:, product_variant_id:, quantity:)
      requested_quantity = Integer(quantity)
      raise InvalidItemError, "quantity must be positive" unless requested_quantity.positive?

      with_locked_active_cart(store_id: store_id, access_token: access_token) do |cart|
        variant = ProductVariant.find_by!(id: product_variant_id, store_id: cart.store_id, status: "active")
        product = Product.find_by!(id: variant.product_id, store_id: cart.store_id, status: "active")
        raise InvalidItemError, "product is not published" if product.published_at.nil? || product.published_at > Time.current

        if cart.currency.present? && cart.currency != variant.currency
          raise CurrencyMismatchError, "all cart items must use the same currency"
        end

        cart.update!(currency: variant.currency) if cart.currency.nil?
        item = CartItem.find_or_initialize_by(
          tenant_id: Current.tenant_id,
          store_id: cart.store_id,
          cart_id: cart.id,
          product_variant_id: variant.id
        )
        item.quantity = item.persisted? ? item.quantity + requested_quantity : requested_quantity
        item.save!
        item
      end
    rescue ArgumentError, TypeError
      raise InvalidItemError, "quantity must be an integer"
    end

    def self.set_item_quantity(store_id:, access_token:, product_variant_id:, quantity:)
      requested_quantity = Integer(quantity)
      raise InvalidItemError, "quantity must be positive" unless requested_quantity.positive?

      with_locked_active_cart(store_id: store_id, access_token: access_token) do |cart|
        item = CartItem.find_by!(cart_id: cart.id, product_variant_id: product_variant_id)
        item.update!(quantity: requested_quantity)
        item
      end
    rescue ArgumentError, TypeError
      raise InvalidItemError, "quantity must be an integer"
    end

    def self.remove_item(store_id:, access_token:, product_variant_id:)
      with_locked_active_cart(store_id: store_id, access_token: access_token) do |cart|
        CartItem.find_by!(cart_id: cart.id, product_variant_id: product_variant_id).destroy!
      end
    end

    def self.read(store_id:, access_token:)
      require_tenant!
      store = Store.find(store_id)
      cart = Cart.find_by!(store_id: store.id, access_token_digest: digest(access_token))
      expire_if_needed!(cart)
      cart
    end

    def self.with_locked_active_cart(store_id:, access_token:)
      require_tenant!
      result = nil
      ApplicationRecord.transaction(requires_new: true) do
        store = Store.find_by!(id: store_id, status: "active")
        cart = Cart.lock.find_by!(store_id: store.id, access_token_digest: digest(access_token))
        expire_if_needed!(cart)
        raise InvalidCartError, "cart is not active" unless cart.status == "active"

        result = yield cart
      end
      result
    end

    def self.expire_if_needed!(cart)
      return unless cart.expired? && cart.status == "active"

      cart.update!(status: "expired")
      raise InvalidCartError, "cart has expired"
    end
    private_class_method :expire_if_needed!

    def self.require_tenant!
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?
    end
    private_class_method :require_tenant!

    def self.digest(token)
      raise InvalidCartError, "cart token is required" if token.blank?

      Digest::SHA256.hexdigest(token.to_s)
    end
    private_class_method :digest
  end
end
