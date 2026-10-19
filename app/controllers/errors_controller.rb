class ErrorsController < ApplicationController
  skip_before_action :authenticate!

  def not_found
    render_error(:not_found, "not_found", "No route matches #{request.method} #{request.path}")
  end
end
