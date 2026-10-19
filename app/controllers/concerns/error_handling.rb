# Maps exceptions to consistent JSON error responses:
#
#   { "error": { "code": "validation_failed", "message": "...", "details": { ... } } }
#
# Handlers declared later take precedence, so the catch-all comes first.
module ErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from StandardError, with: :handle_unexpected_error

    rescue_from ActiveRecord::RecordNotFound do |error|
      render_error(:not_found, "not_found", "#{error.model || 'Record'} not found")
    end

    rescue_from ActionController::ParameterMissing, Errors::BadRequest do |error|
      render_error(:bad_request, "bad_request", error.message)
    end

    rescue_from ActionDispatch::Http::Parameters::ParseError do
      render_error(:bad_request, "invalid_json", "Request body is not valid JSON")
    end

    rescue_from ActiveRecord::RecordInvalid, with: :handle_record_invalid

    rescue_from ActiveRecord::RecordNotDestroyed do |error|
      render_error(:conflict, "conflict", error.record.errors.full_messages.to_sentence.presence || error.message)
    end

    # Raised by the database when a concurrent request books an overlapping slot
    # after this request's validation already passed.
    rescue_from ActiveRecord::ExclusionViolation do
      render_error(:conflict, "reservation_conflict", "This time slot overlaps an existing reservation")
    end

    rescue_from ActiveRecord::RecordNotUnique do
      render_error(:conflict, "conflict", "A record with these details already exists")
    end

    rescue_from Errors::InvalidStateTransition do |error|
      render_error(:unprocessable_content, "invalid_state", error.message)
    end

    rescue_from Errors::AuthenticationError do |error|
      response.headers["WWW-Authenticate"] = 'Bearer realm="api"'
      render_error(:unauthorized, "unauthorized", error.message)
    end

    rescue_from Errors::ForbiddenError do |error|
      render_error(:forbidden, "forbidden", error.message)
    end
  end

  private

  def render_error(status, code, message, details: nil)
    body = { code:, message: }
    body[:details] = details if details.present?
    render json: { error: body }, status:
  end

  def handle_record_invalid(error)
    record = error.record

    if record.errors.of_kind?(:base, :overlap)
      render_error(:conflict, "reservation_conflict", record.errors.full_messages.to_sentence)
    else
      render_error(:unprocessable_content, "validation_failed", "Validation failed",
        details: record.errors.to_hash(true))
    end
  end

  def handle_unexpected_error(error)
    raise error if Rails.env.local? # surface full stack traces in development and test

    Rails.logger.error("[#{request.request_id}] #{error.class}: #{error.message}\n#{error.backtrace&.first(10)&.join("\n")}")
    render_error(:internal_server_error, "internal_error",
      "Something went wrong. Reference: #{request.request_id}")
  end
end
