Rails.application.config.filter_parameters += %i[
  password
  password_confirmation
  token
  access_token
  refresh_token
  challenge_token
  recovery_code
  code
  authorization
  secret
  api_key
]
