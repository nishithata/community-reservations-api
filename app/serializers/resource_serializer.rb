module ResourceSerializer
  module_function

  def call(resource)
    {
      id: resource.id,
      name: resource.name,
      description: resource.description,
      category: resource.category,
      location: resource.location,
      capacity: resource.capacity,
      active: resource.active,
      created_at: resource.created_at.iso8601,
      updated_at: resource.updated_at.iso8601
    }
  end
end
