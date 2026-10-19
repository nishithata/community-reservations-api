class ApplicationController < ActionController::API
  include ErrorHandling
  include Authentication
  include Authorization
  include Pagination
end
