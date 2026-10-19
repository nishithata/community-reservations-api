class ResourcePolicy < ApplicationPolicy
  # Browsing the catalog is public so the demo UI can show it before login.
  def show?
    record.active? || admin?
  end

  def create? = admin?
  def update? = admin?
  def destroy? = admin?

  # Members see only active resources; admins can also see inactive ones.
  def self.scope(user, relation = Resource.all)
    user&.admin? ? relation : relation.active
  end
end
