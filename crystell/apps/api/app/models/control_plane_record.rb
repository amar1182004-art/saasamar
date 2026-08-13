class ControlPlaneRecord < ActiveRecord::Base
  self.abstract_class = true

  establish_connection ENV.fetch("CONTROL_PLANE_DATABASE_URL")
end
