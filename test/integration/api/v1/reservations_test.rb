require "test_helper"

class Api::V1::ReservationsTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    @booked = reservations(:member_upcoming)
  end

  def create_reservation(user: @member, **attributes)
    starts_at, ends_at = free_slot
    body = { resource_id: resources(:study_room).id, starts_at: starts_at.iso8601, ends_at: ends_at.iso8601 }
    post api_v1_reservations_url, headers: auth_headers(user), params: { reservation: body.merge(attributes) }, as: :json
  end

  # --- index ---------------------------------------------------------------

  test "requires authentication" do
    get api_v1_reservations_url

    assert_error :unauthorized, "unauthorized"
  end

  test "members see only their own reservations, in chronological order" do
    get api_v1_reservations_url, headers: auth_headers(@member)

    assert_response :ok
    assert_equal [ @member.id ], json["data"].map { it.dig("user", "id") }.uniq
    starts = json["data"].map { it["starts_at"] }
    assert_equal starts.sort, starts
    assert_equal 3, json.dig("meta", "total_count")
  end

  test "admins see everyone's reservations" do
    get api_v1_reservations_url, headers: auth_headers(users(:admin))

    assert_equal Reservation.count, json.dig("meta", "total_count")
  end

  test "filters by status, resource, and time window" do
    get api_v1_reservations_url, headers: auth_headers(@member), params: { status: "cancelled" }
    assert_equal [ reservations(:member_cancelled).id ], json["data"].map { it["id"] }

    get api_v1_reservations_url, headers: auth_headers(@member), params: { resource_id: resources(:study_room).id }
    assert_equal [ @booked.id ], json["data"].map { it["id"] }

    get api_v1_reservations_url, headers: auth_headers(@member), params: { from: Time.current.iso8601 }
    assert_not_includes json["data"].map { it["id"] }, reservations(:member_past).id
  end

  test "rejects invalid filters" do
    get api_v1_reservations_url, headers: auth_headers(@member), params: { status: "maybe" }
    assert_error :bad_request, "bad_request"

    get api_v1_reservations_url, headers: auth_headers(@member), params: { from: "yesterday" }
    assert_error :bad_request, "bad_request"
  end

  test "paginates results" do
    get api_v1_reservations_url, headers: auth_headers(@member), params: { per_page: 2 }

    assert_equal 2, json["data"].size
    assert_equal 2, json.dig("meta", "next_page")
  end

  # --- create ----------------------------------------------------------------

  test "creates a reservation for a free slot" do
    assert_difference "Reservation.count", 1 do
      create_reservation(notes: "Book club")
    end

    assert_response :created
    assert_equal "confirmed", json.dig("data", "status")
    assert_equal "Book club", json.dig("data", "notes")
    assert_equal @member.id, json.dig("data", "user", "id")
    assert_equal api_v1_reservation_url(json.dig("data", "id")), response.location
  end

  test "returns 409 when the slot overlaps an existing reservation" do
    assert_no_difference "Reservation.count" do
      create_reservation(starts_at: (@booked.starts_at + 30.minutes).iso8601, ends_at: (@booked.ends_at + 30.minutes).iso8601)
    end

    assert_error :conflict, "reservation_conflict"
  end

  # Simulates two requests that both pass validation before either commits:
  # the database exclusion constraint must still reject the second booking.
  test "returns 409 when the database rejects a concurrent overlapping booking" do
    Reservation.skip_callback(:validate, :before, :no_overlapping_reservation)

    assert_no_difference "Reservation.count" do
      create_reservation(starts_at: @booked.starts_at.iso8601, ends_at: @booked.ends_at.iso8601)
    end

    assert_error :conflict, "reservation_conflict"
  ensure
    Reservation.set_callback(:validate, :before, :no_overlapping_reservation, if: :confirmed?)
  end

  test "allows booking a slot that was freed by a cancellation" do
    patch cancel_api_v1_reservation_url(@booked), headers: auth_headers(@member)
    create_reservation(user: users(:other_member), starts_at: @booked.starts_at.iso8601, ends_at: @booked.ends_at.iso8601)

    assert_response :created
  end

  test "returns field errors for an invalid time range" do
    starts_at, = free_slot
    create_reservation(starts_at: starts_at.iso8601, ends_at: (starts_at - 1.hour).iso8601)

    assert_error :unprocessable_content, "validation_failed"
    assert_equal [ "Ends at must be after starts_at" ], json.dig("error", "details", "ends_at")
  end

  test "returns validation errors for a missing or unknown resource" do
    create_reservation(resource_id: 0)

    assert_error :unprocessable_content, "validation_failed"
    assert json.dig("error", "details", "resource").present?
  end

  test "returns 400 when the reservation payload is missing" do
    post api_v1_reservations_url, headers: auth_headers(@member), params: {}, as: :json

    assert_error :bad_request, "bad_request"
  end

  test "ignores attempts to book on behalf of another user" do
    create_reservation(user_id: users(:other_member).id)

    assert_response :created
    assert_equal @member.id, json.dig("data", "user", "id")
  end

  # --- show ------------------------------------------------------------------

  test "members can view their own reservation" do
    get api_v1_reservation_url(@booked), headers: auth_headers(@member)

    assert_response :ok
    assert_equal "Study Room", json.dig("data", "resource", "name")
  end

  test "members get 404 for someone else's reservation" do
    get api_v1_reservation_url(reservations(:other_upcoming)), headers: auth_headers(@member)

    assert_error :not_found, "not_found"
  end

  test "admins can view any reservation" do
    get api_v1_reservation_url(reservations(:other_upcoming)), headers: auth_headers(users(:admin))

    assert_response :ok
  end

  # --- cancel ----------------------------------------------------------------

  test "members cancel their own reservation" do
    patch cancel_api_v1_reservation_url(@booked), headers: auth_headers(@member)

    assert_response :ok
    assert_equal "cancelled", json.dig("data", "status")
    assert json.dig("data", "cancelled_at").present?
  end

  test "cancelling twice returns 422 invalid_state" do
    patch cancel_api_v1_reservation_url(reservations(:member_cancelled)), headers: auth_headers(@member)

    assert_error :unprocessable_content, "invalid_state"
  end

  test "cannot cancel a reservation that has ended" do
    patch cancel_api_v1_reservation_url(reservations(:member_past)), headers: auth_headers(@member)

    assert_error :unprocessable_content, "invalid_state"
  end

  test "members cannot cancel someone else's reservation" do
    patch cancel_api_v1_reservation_url(reservations(:other_upcoming)), headers: auth_headers(@member)

    assert_error :not_found, "not_found"
    assert reservations(:other_upcoming).reload.confirmed?
  end

  test "admins can cancel any reservation" do
    patch cancel_api_v1_reservation_url(reservations(:other_upcoming)), headers: auth_headers(users(:admin))

    assert_response :ok
  end
end
