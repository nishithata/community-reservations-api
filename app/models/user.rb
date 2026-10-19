class User < ApplicationRecord
  ROLES = { member: "member", admin: "admin" }.freeze

  has_secure_password

  has_many :reservations, dependent: :restrict_with_error

  enum :role, ROLES, default: :member, validate: true

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, length: { maximum: 255 },
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: true
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true
end
