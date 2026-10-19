# Bearer-token (JWT) authentication. Every endpoint requires a valid token unless
# the controller opts out with `allow_unauthenticated`.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate!
  end

  class_methods do
    # Endpoints that work without a token but still identify the user when one is sent.
    def allow_unauthenticated(**options)
      skip_before_action :authenticate!, **options
      before_action :authenticate_if_token_present, **options
    end
  end

  private

  attr_reader :current_user

  def authenticate!
    token = bearer_token or raise Errors::AuthenticationError
    @current_user = user_from_token(token)
  end

  def authenticate_if_token_present
    token = bearer_token
    @current_user = user_from_token(token) if token
  end

  def bearer_token
    scheme, token = request.authorization.to_s.split(" ", 2)
    token if scheme&.casecmp?("Bearer") && token.present?
  end

  # The role is always read from the database, never trusted from the token,
  # so a demoted admin loses access immediately.
  def user_from_token(token)
    payload = JsonWebToken.decode(token)
    User.find_by(id: payload["sub"]) or raise Errors::AuthenticationError, "User no longer exists"
  end
end
