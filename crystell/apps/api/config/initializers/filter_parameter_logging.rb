Rails.application.config.filter_parameters += %i[
  password
  password_confirmation
  token
  access_token
  refresh_token
  authorization
  secret
  api_key
]
