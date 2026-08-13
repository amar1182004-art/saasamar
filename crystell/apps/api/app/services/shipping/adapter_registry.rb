module Shipping
  class AdapterRegistry
    class UnsupportedProviderError < StandardError; end
    class DisabledProviderError < StandardError; end

    ADAPTERS = {
      "reference_flat_rate" => Shipping::Adapters::ReferenceFlatRate
    }.freeze

    def self.build(account)
      raise DisabledProviderError, "shipping provider account is disabled" unless account.status == "active"

      adapter_class = ADAPTERS[account.provider_key]
      raise UnsupportedProviderError, "unsupported shipping provider: #{account.provider_key}" unless adapter_class

      adapter_class.new(account: account)
    end
  end
end
