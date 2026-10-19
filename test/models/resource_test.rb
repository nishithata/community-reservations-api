require "test_helper"

class ResourceTest < ActiveSupport::TestCase
  test "requires a name and a known category" do
    resource = Resource.new(category: "spaceship")

    assert_not resource.valid?
    assert resource.errors.key?(:name)
    assert resource.errors.key?(:category)
  end

  test "rejects a duplicate name regardless of case" do
    resource = Resource.new(name: "study room", category: :room)

    assert_not resource.valid?
    assert_includes resource.errors[:name], "has already been taken"
  end

  test "requires capacity to be a positive integer when present" do
    assert_not Resource.new(name: "Tiny Room", category: :room, capacity: 0).valid?
    assert Resource.new(name: "Tiny Room", category: :room, capacity: nil).valid?
  end

  test "search matches name or description, case-insensitively" do
    assert_equal [ resources(:study_room) ], Resource.search("WHITEBOARD").to_a
  end

  test "search treats SQL wildcards literally" do
    assert_empty Resource.search("%").to_a
  end

  test "bookings_on returns only confirmed reservations on that UTC day" do
    day = reservations(:member_upcoming).starts_at.to_date

    assert_equal [ reservations(:member_upcoming) ], resources(:study_room).bookings_on(day).to_a
    assert_empty resources(:projector).bookings_on(day).to_a, "cancelled reservations must not block the day"
  end

  test "cannot be destroyed while it has reservations" do
    assert_not resources(:study_room).destroy
    assert resources(:study_room).errors.of_kind?(:base, :"restrict_dependent_destroy.has_many")
  end
end
