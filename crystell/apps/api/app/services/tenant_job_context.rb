class TenantJobContext
  def self.with(envelope)
    data = TenantJobEnvelope.validate!(envelope)
    tenant_id = data.fetch("tenant_id")
    actor_user_id = data["actor_user_id"]

    if actor_user_id
      IdentityScope.with(actor_user_id) do
        TenantScope.with(tenant_id) { yield data.fetch("payload") }
      end
    else
      TenantScope.with(tenant_id) { yield data.fetch("payload") }
    end
  end
end
