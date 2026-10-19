require "test_helper"

class Api::V1::HealthTest < ActionDispatch::IntegrationTest
  test "deep health check verifies the database" do
    get api_v1_health_url

    assert_response :ok
    assert_equal({ "status" => "ok", "database" => "ok" }, json.slice("status", "database"))
  end

  test "liveness probe responds" do
    get rails_health_check_url

    assert_response :ok
  end

  test "root describes the API" do
    get root_url

    assert_response :ok
    assert_equal api_v1_resources_url, json["resources"]
  end

  test "unknown API paths return a JSON 404" do
    get "/api/v1/nope"

    assert_error :not_found, "not_found"
  end
end
