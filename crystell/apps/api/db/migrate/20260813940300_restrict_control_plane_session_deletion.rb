class RestrictControlPlaneSessionDeletion < ActiveRecord::Migration[8.0]
  def up
    execute "REVOKE DELETE ON control_plane_sessions FROM crystell_control_plane_runtime"
  end

  def down
    execute "GRANT DELETE ON control_plane_sessions TO crystell_control_plane_runtime"
  end
end
