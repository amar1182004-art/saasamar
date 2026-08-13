class TenantOwnershipTransfer
  class InvalidTargetError < StandardError; end

  Result = Data.define(:target_user_id)

  def self.call(target_membership_id:)
    raise InvalidTargetError, "tenant context is required" if Current.tenant_id.blank?
    raise InvalidTargetError, "membership context is required" unless Current.membership

    TenantPermission.require!(Current.membership, "ownership.transfer")

    connection = ActiveRecord::Base.connection
    row = connection.exec_query(
      "SELECT crystell.transfer_tenant_ownership($1::uuid) AS target_user_id",
      "TransferTenantOwnership",
      [uuid_attribute("target_membership_id", target_membership_id)]
    ).first

    target_user_id = row&.fetch("target_user_id", nil)
    raise InvalidTargetError, "invalid ownership transfer target" if target_user_id.blank?

    SecurityAudit.record!(
      "tenant.ownership_transferred",
      metadata: {
        target_membership_id: target_membership_id,
        target_user_id: target_user_id
      }
    )

    Result.new(target_user_id: target_user_id)
  rescue ActiveRecord::StatementInvalid => error
    raise InvalidTargetError, "invalid ownership transfer target" if error.message.match?(/ownership|transfer|target/i)

    raise
  end

  def self.uuid_attribute(name, value)
    ActiveRecord::Relation::QueryAttribute.new(name, value.to_s, ActiveRecord::Type::String.new)
  end
  private_class_method :uuid_attribute
end
