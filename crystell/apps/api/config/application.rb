require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module CrystellApi
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true
    config.time_zone = "Cairo"
    config.active_job.queue_adapter = :sidekiq
  end
end
