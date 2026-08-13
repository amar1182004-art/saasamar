class AddControlPlaneMfaReplayGuard < ActiveRecord::Migration[8.0]
  def change
    add_column :control_plane_users, :last_mfa_timestep, :bigint
    add_check_constraint :control_plane_users,
                         "last_mfa_timestep IS NULL OR last_mfa_timestep >= 0",
                         name: "control_plane_users_mfa_timestep_check"
  end
end
