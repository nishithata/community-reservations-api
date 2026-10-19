# GET / gives a human or a client a starting point instead of a bare 404.
class HomeController < ApplicationController
  skip_before_action :authenticate!

  def show
    render json: {
      name: "Community Resource Reservation API",
      version: "v1",
      health: api_v1_health_url,
      resources: api_v1_resources_url,
      docs: "https://github.com/nishithata/community-reservations-api/blob/main/docs/API.md"
    }
  end
end
