module Authorization
  private

  # authorize!(reservation, :cancel?) looks up ReservationPolicy#cancel?
  def authorize!(record, action)
    policy = "#{record.class.name}Policy".constantize.new(current_user, record)
    raise Errors::ForbiddenError unless policy.public_send(action)
  end
end
