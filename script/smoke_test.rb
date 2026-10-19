#!/usr/bin/env ruby
# End-to-end smoke test against a running server, using only the Ruby standard library.
#
#   ruby script/smoke_test.rb                                  # http://localhost:3000
#   ruby script/smoke_test.rb https://your-api.onrender.com    # a deployed instance
#
# Uses the public demo member account from db/seeds.rb. Creates one reservation
# far in the future and cancels it again, so it leaves no booking behind.
require "json"
require "net/http"
require "time"
require "uri"

BASE_URL = URI(ARGV[0] || ENV.fetch("BASE_URL", "http://localhost:3000"))
EMAIL = ENV.fetch("SMOKE_EMAIL", "demo@example.com")
PASSWORD = ENV.fetch("SMOKE_PASSWORD", "demo-password-123")

def request(method, path, body: nil, token: nil)
  uri = BASE_URL + path
  http = Net::HTTP.new(uri.host, uri.port, nil) # nil: never route through an HTTP proxy
  http.use_ssl = uri.scheme == "https"
  req = Net::HTTP.const_get(method.capitalize).new(uri)
  req["Content-Type"] = "application/json"
  req["Accept"] = "application/json"
  req["Authorization"] = "Bearer #{token}" if token
  req.body = body.to_json if body
  res = http.request(req)
  [ res.code.to_i, res.body.to_s.empty? ? {} : JSON.parse(res.body) ]
end

$failures = 0
def check(description, expected_status, actual_status)
  ok = expected_status == actual_status
  $failures += 1 unless ok
  puts "#{ok ? 'PASS' : 'FAIL'}  #{description} (expected #{expected_status}, got #{actual_status})"
end

status, body = request(:get, "/api/v1/health")
check "health check reports database ok", 200, status
abort "API is not healthy: #{body}" unless status == 200

status, body = request(:get, "/api/v1/resources?category=room")
check "public resource listing", 200, status
resource = body.fetch("data").first or abort "No rooms found. Did you run bin/rails db:seed?"

status, body = request(:post, "/api/v1/auth/login", body: { email: EMAIL, password: PASSWORD })
check "demo member logs in", 200, status
token = body.fetch("token")

check "wrong password is rejected", 401,
  request(:post, "/api/v1/auth/login", body: { email: EMAIL, password: "wrong-password" }).first

# A random slot ~60-90 days out keeps repeated runs from colliding.
day = Time.now.utc + (60 + rand(30)) * 86_400
starts_at = Time.utc(day.year, day.month, day.day, 6 + rand(12))
slot = { resource_id: resource["id"], starts_at: starts_at.iso8601, ends_at: (starts_at + 3600).iso8601 }

check "booking without a token is rejected", 401,
  request(:post, "/api/v1/reservations", body: { reservation: slot }).first

status, body = request(:post, "/api/v1/reservations", body: { reservation: slot.merge(notes: "smoke test") }, token:)
check "member books a free slot", 201, status
reservation_id = body.dig("data", "id")

check "overlapping booking returns 409", 409,
  request(:post, "/api/v1/reservations", body: { reservation: slot }, token:).first

check "invalid time range returns 422", 422,
  request(:post, "/api/v1/reservations",
    body: { reservation: slot.merge(ends_at: (starts_at - 3600).iso8601) }, token:).first

status, body = request(:get, "/api/v1/resources/#{resource['id']}/availability?date=#{starts_at.to_date.iso8601}")
check "availability shows the new booking", 200, status
puts "      bookings that day: #{body.dig('data', 'bookings').size}"

status, body = request(:get, "/api/v1/reservations?per_page=5", token:)
check "member lists own reservations (paginated)", 200, status
puts "      meta: #{body['meta']}"

check "member cancels the booking", 200, request(:patch, "/api/v1/reservations/#{reservation_id}/cancel", token:).first
check "cancelling twice returns 422", 422, request(:patch, "/api/v1/reservations/#{reservation_id}/cancel", token:).first

check "members cannot create resources", 403,
  request(:post, "/api/v1/resources", body: { resource: { name: "Smoke Tent", category: "equipment" } }, token:).first

check "unknown API path returns JSON 404", 404, request(:get, "/api/v1/does-not-exist").first

puts
puts $failures.zero? ? "All smoke checks passed." : "#{$failures} smoke check(s) failed."
exit($failures.zero? ? 0 : 1)
