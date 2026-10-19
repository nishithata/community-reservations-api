class Reservation < ApplicationRecord
  STATUSES = { confirmed: "confirmed", cancelled: "cancelled" }.freeze
  MIN_DURATION = 15.minutes
  MAX_DURATION = 8.hours

  belongs_to :user
  belongs_to :resource

  enum :status, STATUSES, default: :confirmed, validate: true

  validates :starts_at, :ends_at, presence: true
  validates :notes, length: { maximum: 500 }
  validate :ends_after_starts
  validate :duration_within_limits
  validate :starts_in_future, on: :create
  validate :resource_bookable, on: :create
  validate :no_overlapping_reservation, if: :confirmed?

  # Half-open interval overlap: [a, b) and [c, d) overlap when a < d and c < b.
  # Matches the '[)' bounds of the database exclusion constraint.
  scope :overlapping, ->(starts_at, ends_at) { where("starts_at < ? AND ends_at > ?", ends_at, starts_at) }
  scope :upcoming, -> { where("ends_at > ?", Time.current) }
  scope :chronological, -> { order(:starts_at, :id) }

  def cancel!
    raise Errors::InvalidStateTransition, "Reservation is already cancelled" if cancelled?
    raise Errors::InvalidStateTransition, "Reservation has already ended" if ends_at <= Time.current

    update!(status: :cancelled, cancelled_at: Time.current)
  end

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after starts_at") if ends_at <= starts_at
  end

  def duration_within_limits
    return if starts_at.blank? || ends_at.blank? || ends_at <= starts_at

    duration = ends_at - starts_at
    errors.add(:base, "Reservation must be at least 15 minutes long") if duration < MIN_DURATION
    errors.add(:base, "Reservation cannot be longer than 8 hours") if duration > MAX_DURATION
  end

  def starts_in_future
    return if starts_at.blank?

    errors.add(:starts_at, "must be in the future") if starts_at <= Time.current
  end

  def resource_bookable
    return if resource.nil?

    errors.add(:resource, "is not available for booking") unless resource.active?
  end

  # Friendly, early check. The database exclusion constraint is the real guarantee
  # when two requests race (see ReservationsController#create).
  def no_overlapping_reservation
    return if starts_at.blank? || ends_at.blank? || resource_id.blank?

    conflict = Reservation.confirmed
      .where(resource_id:)
      .where.not(id:)
      .overlapping(starts_at, ends_at)
      .exists?

    errors.add(:base, :overlap, message: "This time slot overlaps an existing reservation") if conflict
  end
end
