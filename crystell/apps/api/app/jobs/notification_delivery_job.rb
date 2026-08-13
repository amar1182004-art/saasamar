class NotificationDeliveryJob
  include Sidekiq::Job

  sidekiq_options queue: "communications", retry: 8

  def perform(tenant_id, delivery_id)
    TenantSystemAccess.with(tenant_id: tenant_id) do
      Notifications::Dispatcher.call(delivery_id: delivery_id)
    end
  rescue ActiveRecord::RecordNotFound, TenantSystemAccess::ForbiddenError
    nil
  end
end
