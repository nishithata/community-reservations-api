require "test_helper"

class Api::V1::ResourcesTest < ActionDispatch::IntegrationTest
  test "index is public, paginated, and hides inactive resources" do
    get api_v1_resources_url

    assert_response :ok
    names = json["data"].map { it["name"] }
    assert_includes names, "Study Room"
    assert_not_includes names, "Retired Speaker"
    assert_equal({ "page" => 1, "per_page" => 20, "total_count" => 3, "total_pages" => 1,
                   "next_page" => nil, "prev_page" => nil }, json["meta"])
  end

  test "index shows inactive resources to admins" do
    get api_v1_resources_url, headers: auth_headers(users(:admin))

    assert_includes json["data"].map { it["name"] }, "Retired Speaker"
  end

  test "index paginates with page and per_page" do
    get api_v1_resources_url, params: { per_page: 2, page: 2 }

    assert_response :ok
    assert_equal 1, json["data"].size
    assert_equal({ "page" => 2, "per_page" => 2, "total_count" => 3, "total_pages" => 2,
                   "next_page" => nil, "prev_page" => 1 }, json["meta"])
  end

  test "index caps per_page at 100" do
    get api_v1_resources_url, params: { per_page: 1_000 }

    assert_equal 100, json.dig("meta", "per_page")
  end

  test "index filters by category and search term" do
    get api_v1_resources_url, params: { category: "equipment" }
    assert_equal [ "Projector Kit" ], json["data"].map { it["name"] }

    get api_v1_resources_url, params: { q: "garden" }
    assert_equal [ "Garden Plot" ], json["data"].map { it["name"] }
  end

  test "index rejects an unknown category" do
    get api_v1_resources_url, params: { category: "spaceship" }

    assert_error :bad_request, "bad_request"
  end

  test "show returns an active resource" do
    get api_v1_resource_url(resources(:study_room))

    assert_response :ok
    assert_equal "Study Room", json.dig("data", "name")
  end

  test "show returns 404 for inactive resources unless admin" do
    get api_v1_resource_url(resources(:retired)), headers: auth_headers(users(:member))
    assert_error :not_found, "not_found"

    get api_v1_resource_url(resources(:retired)), headers: auth_headers(users(:admin))
    assert_response :ok
  end

  test "show returns 404 for an unknown id" do
    get api_v1_resource_url(id: 0)

    assert_error :not_found, "not_found"
  end

  test "admin creates a resource" do
    assert_difference "Resource.count", 1 do
      post api_v1_resources_url, headers: auth_headers(users(:admin)),
        params: { resource: { name: "Pop-up Tent", category: "equipment", capacity: 10 } }, as: :json
    end

    assert_response :created
    assert_equal api_v1_resource_url(Resource.last), response.location
    assert_equal "Pop-up Tent", json.dig("data", "name")
  end

  test "create accepts unwrapped JSON params" do
    post api_v1_resources_url, headers: auth_headers(users(:admin)),
      params: { name: "Folding Chairs", category: "equipment" }, as: :json

    assert_response :created
  end

  test "create returns validation errors" do
    post api_v1_resources_url, headers: auth_headers(users(:admin)),
      params: { resource: { name: "", category: "spaceship" } }, as: :json

    assert_error :unprocessable_content, "validation_failed"
    assert_equal %w[category name], json.dig("error", "details").keys.sort
  end

  test "members cannot create resources" do
    post api_v1_resources_url, headers: auth_headers(users(:member)),
      params: { resource: { name: "Pop-up Tent", category: "equipment" } }, as: :json

    assert_error :forbidden, "forbidden"
  end

  test "anonymous users cannot create resources" do
    post api_v1_resources_url, params: { resource: { name: "Pop-up Tent", category: "equipment" } }, as: :json

    assert_error :unauthorized, "unauthorized"
  end

  test "create rejects a body that is not valid JSON" do
    post api_v1_resources_url, headers: auth_headers(users(:admin)).merge("Content-Type" => "application/json"),
      params: "{not json"

    assert_error :bad_request, "invalid_json"
  end

  test "admin updates a resource" do
    patch api_v1_resource_url(resources(:study_room)), headers: auth_headers(users(:admin)),
      params: { resource: { capacity: 8, active: false } }, as: :json

    assert_response :ok
    assert_equal 8, resources(:study_room).reload.capacity
    assert_not resources(:study_room).active?
  end

  test "members cannot update resources" do
    patch api_v1_resource_url(resources(:study_room)), headers: auth_headers(users(:member)),
      params: { resource: { capacity: 8 } }, as: :json

    assert_error :forbidden, "forbidden"
  end

  test "admin deletes a resource without reservations" do
    assert_difference "Resource.count", -1 do
      delete api_v1_resource_url(resources(:garden)), headers: auth_headers(users(:admin))
    end

    assert_response :no_content
  end

  test "deleting a resource with reservations returns 409" do
    assert_no_difference "Resource.count" do
      delete api_v1_resource_url(resources(:study_room)), headers: auth_headers(users(:admin))
    end

    assert_error :conflict, "conflict"
  end

  test "availability lists confirmed bookings for the day without exposing who booked" do
    booked = reservations(:member_upcoming)
    get availability_api_v1_resource_url(resources(:study_room)), params: { date: booked.starts_at.to_date.iso8601 }

    assert_response :ok
    assert_equal [ { "starts_at" => booked.starts_at.iso8601, "ends_at" => booked.ends_at.iso8601 } ],
      json.dig("data", "bookings")
  end

  test "availability requires a valid date" do
    get availability_api_v1_resource_url(resources(:study_room))
    assert_error :bad_request, "bad_request"

    get availability_api_v1_resource_url(resources(:study_room)), params: { date: "next tuesday" }
    assert_error :bad_request, "bad_request"
  end
end
