# Application-level errors that map to specific HTTP responses
# (see ErrorHandling concern).
module Errors
  class AuthenticationError < StandardError
    def initialize(message = "Authentication required")
      super
    end
  end

  class ForbiddenError < StandardError
    def initialize(message = "You are not allowed to perform this action")
      super
    end
  end

  class InvalidStateTransition < StandardError; end

  class BadRequest < StandardError; end
end
