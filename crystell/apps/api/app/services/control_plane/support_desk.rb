module ControlPlane
  class SupportDesk
    class InvalidSupportRequestError < StandardError; end
    class NotFoundError < StandardError; end

    VALID_STATUSES = %w[open pending resolved closed].freeze

    def self.list(status: nil, query: nil, limit: 25, offset: 0, request_id: nil, ip_address: nil)
      Permission.require!(ControlPlaneCurrent.user, "support.read")
      normalized_status = status.to_s.presence
      raise InvalidSupportRequestError, "support status is invalid" if normalized_status && !VALID_STATUSES.include?(normalized_status)

      bounded_limit = normalize_limit(limit)
      bounded_offset = normalize_offset(offset)
      connection = ControlPlaneRecord.connection
      rows = connection.select_all(<<~SQL).to_a
        SELECT *
        FROM control_plane_api.support_ticket_directory(
          #{connection.quote(normalized_status)},
          #{connection.quote(query.to_s.first(160).presence)},
          #{bounded_limit},
          #{bounded_offset},
          #{connection.quote(ControlPlaneCurrent.user.id.to_s)}::uuid
        )
      SQL
      AuditWriter.call(
        action: "control_plane.support_queue_viewed",
        target_type: "SupportQueue",
        request_id: request_id,
        ip_address: ip_address,
        metadata: { status: normalized_status, result_count: rows.length, limit: bounded_limit, offset: bounded_offset }.compact
      )
      rows
    end

    def self.thread(ticket_id:, request_id: nil, ip_address: nil)
      Permission.require!(ControlPlaneCurrent.user, "support.read")
      connection = ControlPlaneRecord.connection
      rows = connection.select_all(<<~SQL).to_a
        SELECT * FROM control_plane_api.support_ticket_thread(
          #{connection.quote(ticket_id.to_s)}::uuid,
          #{connection.quote(ControlPlaneCurrent.user.id.to_s)}::uuid
        )
      SQL
      raise NotFoundError, "support ticket not found" if rows.empty?

      AuditWriter.call(
        action: "control_plane.support_ticket_viewed",
        target_type: "SupportTicket",
        target_id: ticket_id,
        request_id: request_id,
        ip_address: ip_address
      )
      rows
    rescue ActiveRecord::StatementInvalid => error
      raise NotFoundError, "support ticket not found" if invalid_uuid?(error)

      raise
    end

    def self.reply(ticket_id:, body:, reason:, request_id: nil, ip_address: nil)
      Permission.require!(ControlPlaneCurrent.user, "support.manage")
      message = body.to_s.strip
      audit_reason = normalize_reason!(reason)
      raise InvalidSupportRequestError, "support message must be between 1 and 5000 characters" unless message.length.between?(1, 5_000)

      connection = ControlPlaneRecord.connection
      message_id = connection.select_value(<<~SQL)
        SELECT control_plane_api.append_support_reply(
          #{connection.quote(ticket_id.to_s)}::uuid,
          #{connection.quote(ControlPlaneCurrent.user.id.to_s)}::uuid,
          #{connection.quote(message)}
        )
      SQL
      AuditWriter.call(
        action: "control_plane.support_replied",
        target_type: "SupportTicket",
        target_id: ticket_id,
        request_id: request_id,
        ip_address: ip_address,
        reason: audit_reason,
        metadata: { message_id: message_id }
      )
      message_id
    rescue ActiveRecord::StatementInvalid => error
      map_database_error!(error)
    end

    def self.attachment_preview(ticket_id:, attachment_id:, request_id: nil, ip_address: nil)
      Permission.require!(ControlPlaneCurrent.user, "support.read")
      connection = ControlPlaneRecord.connection
      row = connection.select_one(<<~SQL)
        SELECT * FROM control_plane_api.support_attachment(
          #{connection.quote(ticket_id.to_s)}::uuid,
          #{connection.quote(attachment_id.to_s)}::uuid,
          #{connection.quote(ControlPlaneCurrent.user.id.to_s)}::uuid
        )
      SQL
      raise NotFoundError, "support attachment not found" unless row

      AuditWriter.call(
        action: "control_plane.support_attachment_viewed",
        target_type: "SupportAttachment",
        target_id: attachment_id,
        request_id: request_id,
        ip_address: ip_address,
        metadata: { ticket_id: ticket_id, filename: row.fetch("filename") }
      )
      {
        preview_url: Storage::ObjectStore.presigned_get(key: row.fetch("object_key")),
        filename: row.fetch("filename"),
        content_type: row.fetch("content_type"),
        byte_size: row.fetch("byte_size").to_i
      }
    rescue ActiveRecord::StatementInvalid => error
      raise NotFoundError, "support attachment not found" if invalid_uuid?(error)

      raise
    end

    def self.transition(ticket_id:, status:, reason:, request_id: nil, ip_address: nil)
      Permission.require!(ControlPlaneCurrent.user, "support.manage")
      normalized_status = status.to_s
      raise InvalidSupportRequestError, "support status is invalid" unless VALID_STATUSES.include?(normalized_status)
      audit_reason = normalize_reason!(reason)
      connection = ControlPlaneRecord.connection
      connection.execute(<<~SQL)
        SELECT control_plane_api.transition_support_ticket(
          #{connection.quote(ticket_id.to_s)}::uuid,
          #{connection.quote(ControlPlaneCurrent.user.id.to_s)}::uuid,
          #{connection.quote(normalized_status)}
        )
      SQL
      AuditWriter.call(
        action: "control_plane.support_status_changed",
        target_type: "SupportTicket",
        target_id: ticket_id,
        request_id: request_id,
        ip_address: ip_address,
        reason: audit_reason,
        metadata: { status: normalized_status }
      )
      true
    rescue ActiveRecord::StatementInvalid => error
      map_database_error!(error)
    end

    def self.normalize_reason!(value)
      reason = value.to_s.strip
      raise InvalidSupportRequestError, "reason must be between 3 and 500 characters" unless reason.length.between?(3, 500)

      reason
    end
    private_class_method :normalize_reason!

    def self.normalize_limit(value)
      [[Integer(value || 25), 1].max, 100].min
    rescue ArgumentError, TypeError
      25
    end
    private_class_method :normalize_limit

    def self.normalize_offset(value)
      [Integer(value || 0), 0].max
    rescue ArgumentError, TypeError
      0
    end
    private_class_method :normalize_offset

    def self.invalid_uuid?(error)
      error.cause.is_a?(PG::InvalidTextRepresentation)
    end
    private_class_method :invalid_uuid?

    def self.map_database_error!(error)
      message = error.message
      raise NotFoundError, "support ticket not found" if message.include?("support_ticket_not_found") || invalid_uuid?(error)
      raise InvalidSupportRequestError, "support ticket is closed" if message.include?("support_ticket_closed")
      raise InvalidSupportRequestError, "support request is invalid" if message.include?("support_")

      raise error
    end
    private_class_method :map_database_error!
  end
end
