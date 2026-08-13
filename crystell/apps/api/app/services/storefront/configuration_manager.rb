require "json"

module Storefront
  class ConfigurationManager
    class MissingTenantContextError < StandardError; end
    class InvalidConfigurationError < StandardError; end

    DEFAULT_CONFIG = {
      "theme_key" => "default",
      "locale" => "en",
      "currency_code" => "USD",
      "settings" => {}
    }.freeze
    ALLOWED_CONFIG_KEYS = DEFAULT_CONFIG.keys.freeze
    MAX_CONFIG_BYTES = 65_536
    THEME_KEY_PATTERN = /\A[a-z0-9][a-z0-9_-]{0,63}\z/
    LOCALE_PATTERN = /\A[a-z]{2,3}(?:-[A-Z]{2})?\z/
    CURRENCY_PATTERN = /\A[A-Z]{3}\z/

    Result = Data.define(
      :id,
      :store_id,
      :status,
      :draft_config,
      :published_config,
      :draft_version,
      :published_version,
      :published_at,
      :lock_version
    )

    def self.read(store_id:)
      require_tenant!
      TenantPermission.require!(Current.membership, "catalog.read")
      store = Store.find(store_id)
      record = StorefrontConfiguration.find_by(store_id: store.id)

      build_result(record, store.id)
    end

    def self.update(store_id:, status: nil, config: {})
      require_tenant!
      TenantPermission.require!(Current.membership, "catalog.manage")
      store = Store.find(store_id)
      normalized_patch = normalize_patch!(config)
      normalized_status = normalize_status(status)
      result = nil

      ApplicationRecord.transaction(requires_new: true) do
        record = find_or_create!(store)
        record.with_lock do
          attributes = {}

          unless normalized_patch.empty?
            candidate = validate_config!(deep_merge(current_draft(record), normalized_patch))
            attributes[:draft_config] = candidate
            attributes[:draft_version] = record.draft_version + 1
          end

          attributes[:status] = normalized_status if normalized_status
          record.update!(attributes) unless attributes.empty?
          result = build_result(record, store.id)
        end
      end

      result
    end

    def self.publish(store_id:)
      require_tenant!
      TenantPermission.require!(Current.membership, "catalog.manage")
      store = Store.find(store_id)
      result = nil

      ApplicationRecord.transaction(requires_new: true) do
        record = find_or_create!(store)
        record.with_lock do
          draft = validate_config!(current_draft(record))
          unless record.published_version == record.draft_version && record.published_config == draft
            record.update!(
              published_config: deep_copy(draft),
              published_version: record.draft_version,
              published_at: Time.current
            )
          end
          result = build_result(record, store.id)
        end
      end

      result
    end

    def self.require_tenant!
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank?
    end
    private_class_method :require_tenant!

    def self.find_or_create!(store)
      StorefrontConfiguration.create_or_find_by!(
        tenant_id: Current.tenant_id,
        store_id: store.id
      )
    end
    private_class_method :find_or_create!

    def self.current_draft(record)
      DEFAULT_CONFIG.deep_merge((record.draft_config || {}).deep_stringify_keys)
    end
    private_class_method :current_draft

    def self.normalize_patch!(config)
      patch = config.respond_to?(:to_h) ? config.to_h.deep_stringify_keys : nil
      raise InvalidConfigurationError, "config must be an object" unless patch.is_a?(Hash)

      unknown = patch.keys - ALLOWED_CONFIG_KEYS
      raise InvalidConfigurationError, "unknown config keys: #{unknown.sort.join(', ')}" if unknown.any?

      patch["currency_code"] = patch["currency_code"].to_s.upcase if patch.key?("currency_code")
      patch
    end
    private_class_method :normalize_patch!

    def self.normalize_status(status)
      return nil if status.nil?

      value = status.to_s
      raise InvalidConfigurationError, "status must be offline or online" unless %w[offline online].include?(value)

      value
    end
    private_class_method :normalize_status

    def self.validate_config!(config)
      candidate = config.deep_stringify_keys
      unknown = candidate.keys - ALLOWED_CONFIG_KEYS
      raise InvalidConfigurationError, "unknown config keys: #{unknown.sort.join(', ')}" if unknown.any?
      raise InvalidConfigurationError, "theme_key is invalid" unless THEME_KEY_PATTERN.match?(candidate.fetch("theme_key", ""))
      raise InvalidConfigurationError, "locale is invalid" unless LOCALE_PATTERN.match?(candidate.fetch("locale", ""))
      raise InvalidConfigurationError, "currency_code is invalid" unless CURRENCY_PATTERN.match?(candidate.fetch("currency_code", ""))
      raise InvalidConfigurationError, "settings must be an object" unless candidate.fetch("settings", {}).is_a?(Hash)
      raise InvalidConfigurationError, "storefront config is too large" if JSON.generate(candidate).bytesize > MAX_CONFIG_BYTES

      candidate
    end
    private_class_method :validate_config!

    def self.deep_merge(base, patch)
      base.deep_merge(patch) do |_key, old_value, new_value|
        old_value.is_a?(Hash) && new_value.is_a?(Hash) ? old_value.deep_merge(new_value) : new_value
      end
    end
    private_class_method :deep_merge

    def self.deep_copy(value)
      JSON.parse(JSON.generate(value))
    end
    private_class_method :deep_copy

    def self.build_result(record, store_id)
      if record
        Result.new(
          id: record.id,
          store_id: store_id,
          status: record.status,
          draft_config: deep_copy(current_draft(record)),
          published_config: deep_copy(DEFAULT_CONFIG.deep_merge((record.published_config || {}).deep_stringify_keys)),
          draft_version: record.draft_version,
          published_version: record.published_version,
          published_at: record.published_at,
          lock_version: record.lock_version
        )
      else
        Result.new(
          id: nil,
          store_id: store_id,
          status: "offline",
          draft_config: deep_copy(DEFAULT_CONFIG),
          published_config: deep_copy(DEFAULT_CONFIG),
          draft_version: 0,
          published_version: 0,
          published_at: nil,
          lock_version: 0
        )
      end
    end
    private_class_method :build_result
  end
end
