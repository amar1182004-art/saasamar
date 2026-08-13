ENV["RAILS_ENV"] ||= "test"
require File.expand_path("../config/environment", __dir__)
require "rspec/rails"
require_relative "spec_helper"

RSpec.configure do |config|
  config.use_transactional_fixtures = false
end
