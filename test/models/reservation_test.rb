require "test_helper"

class ReservationTest < ActiveSupport::TestCase
  setup do
    @booked = reservations(:member_upcoming) # study_room, 10:00-12:00 in two days
  end

  def build_reservation(**attributes)
    starts_at = 5.days.from_now.utc.change(hour: 9)
    Reservation.new({
      user: users(:member), resource: resources(:study_room),
      starts_at:, ends_at: starts_at + 1.hour
    }.merge(attributes))
  end

  test "is valid for a free future slot" do
    assert build_reservation.valid?
  end

  test "rejects an end time before the start time" do
    reservation = build_reservation(ends_at: 5.days.from_now.utc.change(hour: 8))

    assert_not reservation.valid?
    assert_includes reservation.errors[:ends_at], "must be after starts_at"
  end

  test "rejects a start time in the past" do
    reservation = build_reservation(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

    assert_not reservation.valid?
    assert_includes reservation.errors[:starts_at], "must be in the future"
  end

  test "rejects reservations shorter than 15 minutes or longer than 8 hours" do
    starts_at = 5.days.from_now.utc.change(hour: 9)

    assert_not build_reservation(starts_at:, ends_at: starts_at + 10.minutes).valid?
    assert_not build_reservation(starts_at:, ends_at: starts_at + 9.hours).valid?
  end

  test "rejects a slot that overlaps a confirmed reservation" do
    reservation = build_reservation(starts_at: @booked.starts_at + 30.minutes, ends_at: @booked.ends_at + 1.hour)

    assert_not reservation.valid?
    assert reservation.errors.of_kind?(:base, :overlap)
  end

  test "allows back-to-back reservations" do
    assert build_reservation(starts_at: @booked.ends_at, ends_at: @booked.ends_at + 1.hour).valid?
    assert build_reservation(starts_at: @booked.starts_at - 1.hour, ends_at: @booked.starts_at).valid?
  end

  test "allows booking over a cancelled reservation" do
    cancelled = reservations(:member_cancelled)

    assert build_reservation(resource: cancelled.resource, starts_at: cancelled.starts_at, ends_at: cancelled.ends_at).valid?
  end

  test "allows the same time slot on a different resource" do
    assert build_reservation(resource: resources(:garden), starts_at: @booked.starts_at, ends_at: @booked.ends_at).valid?
  end

  test "rejects booking an inactive resource" do
    reservation = build_reservation(resource: resources(:retired))

    assert_not reservation.valid?
    assert_includes reservation.errors[:resource], "is not available for booking"
  end

  # These two tests bypass model validation on purpose, to prove the database
  # enforces the rules on its own (e.g. when two requests race each other).
  test "database exclusion constraint rejects overlapping confirmed reservations" do
    overlapping = build_reservation(starts_at: @booked.starts_at + 30.minutes, ends_at: @booked.ends_at)

    assert_raises(ActiveRecord::ExclusionViolation) { overlapping.save!(validate: false) }
  end

  test "database check constraint rejects an end time before the start time" do
    invalid = build_reservation(ends_at: 5.days.from_now.utc.change(hour: 8))

    assert_raises(ActiveRecord::CheckViolation) { invalid.save!(validate: false) }
  end

  test "cancel! marks the reservation cancelled and records when" do
    freeze_time do
      @booked.cancel!

      assert @booked.reload.cancelled?
      assert_equal Time.current, @booked.cancelled_at
    end
  end

  test "cancel! refuses an already cancelled reservation" do
    assert_raises(Errors::InvalidStateTransition) { reservations(:member_cancelled).cancel! }
  end

  test "cancel! refuses a reservation that has already ended" do
    assert_raises(Errors::InvalidStateTransition) { reservations(:member_past).cancel! }
  end
end
