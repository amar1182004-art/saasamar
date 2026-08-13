class ExpireInventoryReservationJob
  include Sidekiq::Job

  sidekiq_options queue: "inventory", retry: 5

  def perform(tenant_id, reservation_id)
    TenantSystemAccess.with(tenant_id: tenant_id) do
      Inventory::ExpiredReservation.call(reservation_id: reservation_id)
    end
  rescue ActiveRecord::RecordNotFound, TenantSystemAccess::ForbiddenError
    nil
  end
end
