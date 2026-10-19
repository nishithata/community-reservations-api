#!/usr/bin/env ruby
# Fires many simultaneous requests for the SAME slot at a running server.
# Exactly one should succeed (201); every other request must get 409, whether it
# was stopped by the model validation or by the database exclusion constraint
# (or 429 if the per-user rate limit is reached).
#
#   ruby script/race_test.rb [BASE_URL] [CONCURRENCY]
require "json"
require "net/http"
require "time"
require "uri"

BASE_URL = URI(ARGV[0] || "http://localhost:3000")
CONCURRENCY = Integer(ARGV[1] || 10)

def post(path, body, token = nil)
  uri = BASE_URL + path
  http = Net::HTTP.new(uri.host, uri.port, nil)
  http.use_ssl = uri.scheme == "https"
  req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
  req["Authorization"] = "Bearer #{token}" if token
  req.body = body.to_json
  res = http.request(req)
  [ res.code.to_i, JSON.parse(res.body) ]
end

_, login = post("/api/v1/auth/login", { email: "demo@example.com", password: "demo-password-123" })
token = login.fetch("token")

resources = JSON.parse(Net::HTTP.new(BASE_URL.host, BASE_URL.port, nil).tap { it.use_ssl = BASE_URL.scheme == "https" }
  .get("/api/v1/resources?category=equipment").body)
resource_id = resources.dig("data", 0, "id")

day = Time.now.utc + (120 + rand(60)) * 86_400
starts_at = Time.utc(day.year, day.month, day.day, 6 + rand(12))
slot = { reservation: { resource_id:, starts_at: starts_at.iso8601, ends_at: (starts_at + 3600).iso8601 } }

gate = Queue.new
threads = Array.new(CONCURRENCY) do
  Thread.new do
    gate.pop # wait so all requests start together
    post("/api/v1/reservations", slot, token)
  end
end
CONCURRENCY.times { gate << :go }
results = threads.map(&:value)

statuses = results.map(&:first).tally
puts "Sent #{CONCURRENCY} simultaneous bookings for #{slot[:reservation][:starts_at]}: #{statuses}"

created = results.select { it.first == 201 }
created.each { |_, body| puts "Winner: reservation ##{body.dig('data', 'id')}" }

# 429s are fine too: the per-user rate limit (30 bookings/minute) may kick in on repeated runs.
ok = statuses[201] == 1 && (statuses.keys - [ 201, 409, 429 ]).empty?
puts "Note: #{statuses[429]} request(s) were rate limited (429)." if statuses[429]
puts ok ? "PASS: exactly one booking succeeded; the rest were rejected." : "FAIL: unexpected outcome."

# Clean up so the demo calendar stays tidy.
created.each do |_, body|
  uri = BASE_URL + "/api/v1/reservations/#{body.dig('data', 'id')}/cancel"
  http = Net::HTTP.new(uri.host, uri.port, nil)
  http.use_ssl = uri.scheme == "https"
  http.request(Net::HTTP::Patch.new(uri, "Authorization" => "Bearer #{token}"))
end
exit(ok ? 0 : 1)
