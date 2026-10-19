class ReservationPolicy < ApplicationPolicy
  def show? = owner? || admin?
  def cancel? = owner? || admin?

  # Members see their own reservations; admins see everyone's.
  def self.scope(user, relation = Reservation.all)
    user.admin? ? relation : relation.where(user:)
  end

  private

  def owner?
    record.user_id == user.id
  end
end
