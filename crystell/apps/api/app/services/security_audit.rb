require "json"

class SecurityAudit
  def self.record!(event_type, metadata: {})
    connection = ActiveRecord::Base.connection
    binds = [
      query_attribute("event_type", event_type.to_s),
      query_attribute("audit_metadata", JSON.generate(metadata))
    ]

    connection.exec_query(
      "SELECT crystell.append_current_security_event($1, $2::jsonb) AS event_id",
      "SecurityAudit",
      binds
    ).first&.fetch("event_id")
  end

  def self.query_attribute(name, value)
    ActiveRecord::Relation::QueryAttribute.new(
      name,
      value,
      ActiveRecord::Type::String.new
    )
  end
  private_class_method :query_attribute
end
