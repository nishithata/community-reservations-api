module Api
  module V1
    class AuthController < ApplicationController
      allow_unauthenticated only: %i[register login]
      wrap_parameters false

      rate_limit to: 10, within: 1.minute, only: :login, with: :render_rate_limited
      rate_limit to: 5, within: 10.minutes, only: :register, with: :render_rate_limited

      # POST /api/v1/auth/register
      # Self-service sign-ups are always members; admins are created by seeds or the console.
      def register
        user = User.create!(params.permit(:name, :email, :password))
        render json: token_response(user), status: :created
      end

      # POST /api/v1/auth/login
      def login
        credentials = params.permit(:email, :password)
        user = User.authenticate_by(email: credentials[:email].to_s, password: credentials[:password].to_s)
        raise Errors::AuthenticationError, "Invalid email or password" unless user

        render json: token_response(user)
      end

      # GET /api/v1/me
      def me
        render json: { data: UserSerializer.call(current_user) }
      end

      private

      def token_response(user)
        {
          token: JsonWebToken.encode(user),
          token_type: "Bearer",
          expires_in: JsonWebToken::TTL.to_i,
          user: UserSerializer.call(user)
        }
      end

      def render_rate_limited
        response.headers["Retry-After"] = "60"
        render_error(:too_many_requests, "rate_limited", "Too many attempts. Please try again shortly.")
      end
    end
  end
end
