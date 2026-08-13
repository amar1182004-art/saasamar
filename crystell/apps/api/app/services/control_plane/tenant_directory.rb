module ControlPlane
  class TenantDirectory
    def self.call(query: nil, limit: 25, offset: 0, request_id: nil, ip_address: nil)
      user = ControlPlaneCurrent.user
      Permission.require!(user, "tenant.read")

      normalized_limit = normalize_limit(limit)
      normalized_offset = normalize_offset(offset)
      connection = ControlPlaneRecord.connection
      rows = connection.select_all(<<~SQL).to_a
        SELECT *
        FROM control_plane_api.tenant_directory(
          #{connection.quote(query.to_s.presence)},
          #{normalized_limit},
          #{normalized_offset}
        )
      SQL

      AuditWriter.call(
        action: "control_plane.tenant_directory_viewed",
        target_type: "TenantDirectory",
        request_id: request_id,
        ip_address: ip_address,
        metadata: {
          "query" => query.to_s.first(120).presence,
          "limit" => normalized_limit,
          "offset" => normalized_offset,
          "result_count" => rows.length
        }.compact
      )

      rows
    end

    def self.normalize_limit(value)
      [[Integer(value), 1].max, 100].min
    rescue ArgumentError, TypeError
      25
    end
    private_class_method :normalize_limit

    def self.normalize_offset(value)
      [Integer(value), 0].max
    rescue ArgumentError, TypeError
      0
    end
    private_class_method :normalize_offset
  end
end
