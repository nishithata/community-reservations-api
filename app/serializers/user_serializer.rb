module UserSerializer
  module_function

  def call(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      created_at: user.created_at.iso8601
    }
  end
end
