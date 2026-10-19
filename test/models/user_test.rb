require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build_user(**attributes)
    User.new({ name: "Test User", email: "new@test.example", password: "password123" }.merge(attributes))
  end

  test "is valid with name, email and password" do
    assert build_user.valid?
  end

  test "defaults to the member role" do
    assert build_user.member?
  end

  test "normalizes email to lowercase without surrounding spaces" do
    assert_equal "mixed@test.example", build_user(email: "  Mixed@Test.Example ").email
  end

  test "rejects a duplicate email regardless of case" do
    user = build_user(email: "MEMBER@test.example")

    assert_not user.valid?
    assert_includes user.errors[:email], "has already been taken"
  end

  test "rejects an invalid email" do
    assert_not build_user(email: "not-an-email").valid?
  end

  test "requires a password of at least 8 characters" do
    user = build_user(password: "short")

    assert_not user.valid?
    assert user.errors.of_kind?(:password, :too_short)
  end

  test "rejects an unknown role" do
    user = build_user(role: "superuser")

    assert_not user.valid?
    assert user.errors.key?(:role)
  end

  test "authenticates with the correct password only" do
    assert_equal users(:member), User.authenticate_by(email: "member@test.example", password: "password123")
    assert_nil User.authenticate_by(email: "member@test.example", password: "wrong-password")
  end
end
