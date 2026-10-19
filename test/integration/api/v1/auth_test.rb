require "test_helper"

class Api::V1::AuthTest < ActionDispatch::IntegrationTest
  test "register creates a member and returns a token" do
    assert_difference "User.count", 1 do
      post api_v1_auth_register_url, params: { name: "New Person", email: "New@Test.Example", password: "password123" }, as: :json
    end

    assert_response :created
    assert_equal "Bearer", json["token_type"]
    assert json["token"].present?
    assert_equal "new@test.example", json.dig("user", "email")
    assert_equal "member", json.dig("user", "role")
  end

  test "register ignores attempts to self-assign the admin role" do
    post api_v1_auth_register_url,
      params: { name: "Sneaky", email: "sneaky@test.example", password: "password123", role: "admin" }, as: :json

    assert_response :created
    assert User.find_by!(email: "sneaky@test.example").member?
  end

  test "register returns field-level validation errors" do
    post api_v1_auth_register_url, params: { name: "", email: "member@test.example", password: "short" }, as: :json

    assert_error :unprocessable_content, "validation_failed"
    assert_equal %w[email name password].sort, json.dig("error", "details").keys.sort
  end

  test "login returns a token for valid credentials" do
    post api_v1_auth_login_url, params: { email: "MEMBER@test.example", password: "password123" }, as: :json

    assert_response :ok
    assert_equal users(:member).id, JsonWebToken.decode(json["token"])["sub"]
  end

  test "login rejects a wrong password without revealing which field was wrong" do
    post api_v1_auth_login_url, params: { email: "member@test.example", password: "wrong-password" }, as: :json

    assert_error :unauthorized, "unauthorized"
    assert_equal "Invalid email or password", json.dig("error", "message")
  end

  test "login rejects an unknown email" do
    post api_v1_auth_login_url, params: { email: "nobody@test.example", password: "password123" }, as: :json

    assert_error :unauthorized, "unauthorized"
  end

  test "me returns the current user" do
    get api_v1_me_url, headers: auth_headers(users(:admin))

    assert_response :ok
    assert_equal "admin", json.dig("data", "role")
  end

  test "me requires a token" do
    get api_v1_me_url

    assert_error :unauthorized, "unauthorized"
    assert_match "Bearer", response.headers["WWW-Authenticate"]
  end

  test "me rejects a malformed token" do
    get api_v1_me_url, headers: { "Authorization" => "Bearer not-a-real-token" }

    assert_error :unauthorized, "unauthorized"
    assert_equal "Token is invalid", json.dig("error", "message")
  end

  test "me rejects an expired token" do
    token = JsonWebToken.encode(users(:member), expires_at: 1.minute.ago)
    get api_v1_me_url, headers: { "Authorization" => "Bearer #{token}" }

    assert_error :unauthorized, "unauthorized"
    assert_equal "Token has expired", json.dig("error", "message")
  end

  test "me rejects a token signed with a different secret" do
    forged = JWT.encode({ sub: users(:admin).id, exp: 1.hour.from_now.to_i }, "attacker-secret", "HS256")
    get api_v1_me_url, headers: { "Authorization" => "Bearer #{forged}" }

    assert_error :unauthorized, "unauthorized"
  end
end
