module Payment
  class AdapterRegistry
    class UnsupportedProviderError < StandardError; end
    class DisabledProviderError < StandardError; end

    ADAPTERS = {
      "reference_hmac" => Payment::Adapters::ReferenceHmac
    }.freeze

    def self.build(account)
      raise DisabledProviderError, "payment provider account is disabled" unless account.status == "active"

      adapter_class = ADAPTERS[account.provider_key]
      raise UnsupportedProviderError, "unsupported payment provider: #{account.provider_key}" unless adapter_class

      adapter_class.new(account: account)
    end
  end
end
