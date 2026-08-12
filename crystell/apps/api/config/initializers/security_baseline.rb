Rails.application.config.action_dispatch.default_headers.merge!(
  "X-Content-Type-Options" => "nosniff",
  "X-Frame-Options" => "DENY",
  "Referrer-Policy" => "strict-origin-when-cross-origin",
  "Permissions-Policy" => "camera=(), microphone=(), geolocation=()"
)

if Rails.env.production?
  secret = ENV["SECRET_KEY_BASE"].to_s
  forbidden = ["", "change-me-local-only", "development-only-change-me"]

  raise "SECRET_KEY_BASE must be configured securely" if forbidden.include?(secret) || secret.length < 64
end
