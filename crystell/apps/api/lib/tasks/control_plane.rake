namespace :control_plane do
  desc "Bootstrap the first Crystell control-plane owner"
  task bootstrap_owner: :environment do
    email = ENV.fetch("CONTROL_PLANE_BOOTSTRAP_EMAIL")
    password = ENV.fetch("CONTROL_PLANE_BOOTSTRAP_PASSWORD")
    mfa_secret = ENV["CONTROL_PLANE_BOOTSTRAP_MFA_SECRET"]

    result = ControlPlane::BootstrapOwner.call(
      email: email,
      password: password,
      mfa_secret: mfa_secret
    )

    puts "Control-plane owner created: #{result.user.email}"
    puts "MFA secret (store securely, shown once): #{result.mfa_secret}"
  end
end
