# Allow the browser demo UI (e.g. on Vercel) to call this API.
#
# The API authenticates with bearer tokens, not cookies, so credentials are not
# allowed cross-origin. Set CORS_ORIGINS to a comma-separated list of origins in
# production to restrict which sites may call the API from a browser.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*ENV.fetch("CORS_ORIGINS", "*").split(",").map(&:strip))

    resource "/api/*",
      headers: :any,
      methods: %i[get post patch put delete options head],
      expose: %w[Retry-After],
      max_age: 600
  end
end
