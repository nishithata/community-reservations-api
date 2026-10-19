module ReservationSerializer
  module_function

  def call(reservation)
    {
      id: reservation.id,
      status: reservation.status,
      starts_at: reservation.starts_at.iso8601,
      ends_at: reservation.ends_at.iso8601,
      notes: reservation.notes,
      cancelled_at: reservation.cancelled_at&.iso8601,
      resource: { id: reservation.resource.id, name: reservation.resource.name },
      user: { id: reservation.user.id, name: reservation.user.name },
      created_at: reservation.created_at.iso8601
    }
  end
end
