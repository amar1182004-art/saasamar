class IdentityScope
  class MissingUserError < StandardError; end

  def self.with(user_id)
    raise MissingUserError, "user_id is required" if user_id.blank?

    previous_user = Current.user

    ActiveRecord::Base.transaction(requires_new: true) do
      connection = ActiveRecord::Base.connection
      connection.execute(
        "SELECT set_config('app.current_user_id', #{connection.quote(user_id.to_s)}, true)"
      )
      yield
    ensure
      Current.user = previous_user
    end
  end
end
