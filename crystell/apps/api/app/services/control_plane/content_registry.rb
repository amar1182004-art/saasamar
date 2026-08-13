module ControlPlane
  class ContentRegistry
    class InvalidContentError < StandardError; end
    class ElevationRequiredError < StandardError; end

    MAX_CONTENT_BYTES = 131_072
    KEY_PATTERN = /\A[a-z0-9][a-z0-9._-]{0,119}\z/
    LOCALE_PATTERN = /\A[a-z]{2,3}(?:-[A-Z]{2})?\z/

    def self.list(kind: nil, locale: nil)
      Permission.require!(ControlPlaneCurrent.user, "content.read")
      scope = ControlPlaneContentDocument.order(:kind, :key, :locale)
      scope = scope.where(kind: normalize_kind!(kind)) if kind.present?
      scope = scope.where(locale: normalize_locale!(locale)) if locale.present?
      scope.limit(200).to_a
    end

    def self.read(key:, locale: "en")
      Permission.require!(ControlPlaneCurrent.user, "content.read")
      ControlPlaneContentDocument.find_by!(key: normalize_key!(key), locale: normalize_locale!(locale))
    end

    def self.update_draft(key:, kind:, locale: "en", content:, reason: nil, request_id: nil, ip_address: nil)
      user = ControlPlaneCurrent.user
      Permission.require!(user, "content.manage")
      normalized_key = normalize_key!(key)
      normalized_kind = normalize_kind!(kind)
      normalized_locale = normalize_locale!(locale)
      normalized_content = normalize_content!(content)
      result = nil

      ControlPlaneRecord.transaction do
        record = ControlPlaneContentDocument.create_or_find_by!(key: normalized_key, locale: normalized_locale) do |created|
          created.kind = normalized_kind
          created.draft_content = {}
          created.published_content = {}
        end
        record.lock!
        raise InvalidContentError, "content kind cannot change" unless record.kind == normalized_kind

        next_version = record.draft_version + 1
        record.update!(draft_content: normalized_content, draft_version: next_version)
        ControlPlaneContentVersion.create!(
          control_plane_content_document_id: record.id,
          control_plane_user_id: user.id,
          version: next_version,
          source: "draft",
          content: normalized_content
        )
        AuditWriter.call(
          action: "control_plane.content_draft_updated",
          target_type: "ControlPlaneContentDocument",
          target_id: record.id,
          request_id: request_id,
          ip_address: ip_address,
          reason: reason,
          metadata: { key: record.key, kind: record.kind, locale: record.locale, version: next_version }
        )
        result = record
      end

      result
    rescue ConfigurationPayload::InvalidPayloadError => error
      raise InvalidContentError, error.message
    end

    def self.publish(key:, locale: "en", reason:, request_id: nil, ip_address: nil)
      user = ControlPlaneCurrent.user
      Permission.require!(user, "content.manage")
      require_elevated!
      normalized_reason = normalize_reason!(reason)
      result = nil

      ControlPlaneRecord.transaction do
        record = ControlPlaneContentDocument.lock.find_by!(key: normalize_key!(key), locale: normalize_locale!(locale))
        raise InvalidContentError, "content has no draft version" if record.draft_version.zero?

        unless record.published_version == record.draft_version && record.published_content == record.draft_content
          record.update!(
            published_content: deep_copy(record.draft_content),
            published_version: record.draft_version,
            published_at: Time.current
          )
        end
        AuditWriter.call(
          action: "control_plane.content_published",
          target_type: "ControlPlaneContentDocument",
          target_id: record.id,
          request_id: request_id,
          ip_address: ip_address,
          reason: normalized_reason,
          metadata: { key: record.key, kind: record.kind, locale: record.locale, version: record.published_version }
        )
        result = record
      end

      result
    end

    def self.rollback(key:, version:, locale: "en", reason:, request_id: nil, ip_address: nil)
      user = ControlPlaneCurrent.user
      Permission.require!(user, "content.manage")
      require_elevated!
      normalized_reason = normalize_reason!(reason)
      result = nil

      ControlPlaneRecord.transaction do
        record = ControlPlaneContentDocument.lock.find_by!(key: normalize_key!(key), locale: normalize_locale!(locale))
        historical = record.versions.find_by!(version: Integer(version))
        next_version = record.draft_version + 1
        restored_content = deep_copy(historical.content)

        record.update!(
          draft_content: restored_content,
          published_content: restored_content,
          draft_version: next_version,
          published_version: next_version,
          published_at: Time.current
        )
        ControlPlaneContentVersion.create!(
          control_plane_content_document_id: record.id,
          control_plane_user_id: user.id,
          version: next_version,
          source: "rollback",
          content: restored_content
        )
        AuditWriter.call(
          action: "control_plane.content_rolled_back",
          target_type: "ControlPlaneContentDocument",
          target_id: record.id,
          request_id: request_id,
          ip_address: ip_address,
          reason: normalized_reason,
          metadata: {
            key: record.key,
            kind: record.kind,
            locale: record.locale,
            restored_from_version: historical.version,
            new_version: next_version
          }
        )
        result = record
      end

      result
    rescue ArgumentError, TypeError
      raise InvalidContentError, "version must be an integer"
    end

    def self.versions(key:, locale: "en")
      Permission.require!(ControlPlaneCurrent.user, "content.read")
      record = ControlPlaneContentDocument.find_by!(key: normalize_key!(key), locale: normalize_locale!(locale))
      record.versions.order(version: :desc).limit(100).to_a
    end

    def self.normalize_content!(content)
      ConfigurationPayload.validate!(content, max_bytes: MAX_CONTENT_BYTES)
    end
    private_class_method :normalize_content!

    def self.normalize_key!(key)
      value = key.to_s
      raise InvalidContentError, "content key is invalid" unless KEY_PATTERN.match?(value)

      value
    end
    private_class_method :normalize_key!

    def self.normalize_kind!(kind)
      value = kind.to_s
      raise InvalidContentError, "content kind is invalid" unless ControlPlaneContentDocument::KINDS.include?(value)

      value
    end
    private_class_method :normalize_kind!

    def self.normalize_locale!(locale)
      value = locale.to_s
      raise InvalidContentError, "locale is invalid" unless LOCALE_PATTERN.match?(value)

      value
    end
    private_class_method :normalize_locale!

    def self.normalize_reason!(reason)
      value = reason.to_s.strip
      raise InvalidContentError, "reason must be between 3 and 500 characters" unless value.length.between?(3, 500)

      value
    end
    private_class_method :normalize_reason!

    def self.require_elevated!
      raise ElevationRequiredError, "privilege elevation is required" unless ControlPlaneCurrent.session&.elevated?
    end
    private_class_method :require_elevated!

    def self.deep_copy(value)
      JSON.parse(JSON.generate(value))
    end
    private_class_method :deep_copy
  end
end
