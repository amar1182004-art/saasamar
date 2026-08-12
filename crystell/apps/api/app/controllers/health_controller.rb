class HealthController < ApplicationController
  def show
    render json: { service: "api", status: "ok" }
  end
end
