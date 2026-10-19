ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
  end
end

module ApiTestHelpers
  def auth_headers(user)
    { "Authorization" => "Bearer #{JsonWebToken.encode(user)}" }
  end

  def json
    response.parsed_body
  end

  def assert_error(status, code)
    assert_response status
    assert_equal code, json.dig("error", "code"), "unexpected error body: #{json}"
  end

  # A future, whole-hour slot that no fixture uses.
  def free_slot(days_ahead: 5, hour: 9, hours: 1)
    starts_at = days_ahead.days.from_now.utc.change(hour:)
    [ starts_at, starts_at + hours.hours ]
  end
end

class ActionDispatch::IntegrationTest
  include ApiTestHelpers
end
