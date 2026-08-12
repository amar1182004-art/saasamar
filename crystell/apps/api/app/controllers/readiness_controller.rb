class ReadinessController < ApplicationController
  def show
    ActiveRecord::Base.connection.select_value("SELECT 1")
    Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/0")).ping

    render json: { service: "api", status: "ready" }
  rescue StandardError => error
    Rails.logger.error("Readiness check failed: #{error.class}")
    render json: { service: "api", status: "not_ready" }, status: :service_unavailable
  end
end
