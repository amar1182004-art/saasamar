module Auth
  class AccountLockout
    THRESHOLD = ENV.fetch("ACCOUNT_LOCKOUT_THRESHOLD", "5").to_i
    LOCK_SECONDS = ENV.fetch("ACCOUNT_LOCKOUT_SECONDS", "900").to_i

    def self.record_failure!(email)
      connection = ActiveRecord::Base.connection
      binds = [
        query_attribute("email", email.to_s.strip.downcase),
        integer_attribute("threshold", THRESHOLD),
        integer_attribute("lock_seconds", LOCK_SECONDS)
      ]

      row = connection.exec_query(
        "SELECT crystell.record_login_failure($1, $2, $3) AS locked_until",
        "RecordLoginFailure",
        binds
      ).first

      parse_time(row&.fetch("locked_until", nil))
    end

    def self.record_success!(user_id)
      connection = ActiveRecord::Base.connection
      connection.exec_query(
        "SELECT crystell.record_login_success($1::uuid)",
        "RecordLoginSuccess",
        [query_attribute("user_id", user_id.to_s)]
      )
      true
    end

    def self.retry_after(locked_until)
      return 1 unless locked_until

      [(locked_until - Time.current).ceil, 1].max
    end

    def self.query_attribute(name, value)
      ActiveRecord::Relation::QueryAttribute.new(name, value, ActiveRecord::Type::String.new)
    end
    private_class_method :query_attribute

    def self.integer_attribute(name, value)
      ActiveRecord::Relation::QueryAttribute.new(name, value, ActiveRecord::Type::Integer.new)
    end
    private_class_method :integer_attribute

    def self.parse_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    end
    private_class_method :parse_time
  end
end
