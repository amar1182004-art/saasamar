module Communications
  class AdapterRegistry
    class UnsupportedProviderError < StandardError; end
    class DisabledProviderError < StandardError; end

    ADAPTERS = {
      "reference" => Communications::Adapters::Reference
    }.freeze

    def self.build(account)
      raise DisabledProviderError, "communication provider account is disabled" unless account.status == "active"

      adapter = ADAPTERS[account.provider_key]
      raise UnsupportedProviderError, "unsupported communication provider: #{account.provider_key}" unless adapter

      adapter.new(account: account)
    end
  end
end
