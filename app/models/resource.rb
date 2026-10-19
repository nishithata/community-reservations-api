class Resource < ApplicationRecord
  CATEGORIES = { room: "room", equipment: "equipment", space: "space", vehicle: "vehicle" }.freeze

  has_many :reservations, dependent: :restrict_with_error

  enum :category, CATEGORIES, validate: true

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, length: { maximum: 120 }, uniqueness: { case_sensitive: false }
  validates :description, length: { maximum: 2_000 }
  validates :location, length: { maximum: 200 }
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :search, ->(term) {
    pattern = "%#{sanitize_sql_like(term.to_s.strip)}%"
    where("resources.name ILIKE :pattern OR resources.description ILIKE :pattern", pattern:)
  }

  # Confirmed reservations that overlap the given UTC day, used by the availability endpoint.
  def bookings_on(date)
    day_start = date.in_time_zone("UTC").beginning_of_day
    reservations.confirmed.overlapping(day_start, day_start + 1.day).order(:starts_at)
  end
end
