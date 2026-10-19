# Plain-Ruby authorization policies: one class per model, one predicate per action.
# Controllers call `authorize!(record, :action?)`, which raises Errors::ForbiddenError.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  private

  def admin?
    user&.admin?
  end
end
