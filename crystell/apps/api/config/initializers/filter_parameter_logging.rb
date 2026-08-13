Rails.application.config.filter_parameters += %i[
  password
  password_digest
  password_confirmation
  token
  token_digest
  access_token
  refresh_token
  challenge_token
  recovery_code
  recovery_code_digests
  code
  authorization
  secret
  encrypted_secret
  encrypted_payload
  api_key
]
