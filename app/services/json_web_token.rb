# Issues and verifies the stateless access tokens used for API authentication.
module JsonWebToken
  ALGORITHM = "HS256".freeze
  TTL = 24.hours

  module_function

  def encode(user, expires_at: TTL.from_now)
    payload = { sub: user.id, role: user.role, exp: expires_at.to_i, iat: Time.current.to_i }
    JWT.encode(payload, secret, ALGORITHM)
  end

  # Returns the decoded payload, or raises Errors::AuthenticationError.
  def decode(token)
    payload, = JWT.decode(token, secret, true, algorithm: ALGORITHM, required_claims: %w[sub exp])
    payload
  rescue JWT::ExpiredSignature
    raise Errors::AuthenticationError, "Token has expired"
  rescue JWT::DecodeError
    raise Errors::AuthenticationError, "Token is invalid"
  end

  def secret
    ENV["JWT_SECRET"].presence || Rails.application.secret_key_base
  end
end
