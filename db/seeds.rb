# Idempotent demo data: safe to run on every deploy (`bin/rails db:seed`).
#
# The member account is public so anyone can try the demo. The admin password
# must come from DEMO_ADMIN_PASSWORD in production, so it is never published.

admin_password = ENV["DEMO_ADMIN_PASSWORD"].presence
if admin_password.nil?
  raise "Set DEMO_ADMIN_PASSWORD to seed the admin account in production" if Rails.env.production?

  admin_password = "admin-password-123"
end

admin = User.find_or_initialize_by(email: "admin@example.com")
admin.update!(name: "Demo Admin", role: :admin, password: admin_password)

member = User.find_or_initialize_by(email: "demo@example.com")
member.update!(name: "Demo Member", role: :member, password: "demo-password-123") if member.new_record?

neighbor = User.find_or_initialize_by(email: "neighbor@example.com")
neighbor.update!(name: "Friendly Neighbor", role: :member, password: SecureRandom.base58(24)) if neighbor.new_record?

resources = [
  { name: "Community Hall", category: :room, location: "Main Building, Floor 1", capacity: 80,
    description: "Large hall for meetings, workshops, and celebrations." },
  { name: "Study Room A", category: :room, location: "Library, Floor 2", capacity: 6,
    description: "Quiet room with a whiteboard and a TV screen." },
  { name: "Garden Plot 12", category: :space, location: "Riverside Community Garden",
    description: "Raised bed with tool shed access." },
  { name: "Projector Kit", category: :equipment, location: "Front Desk",
    description: "1080p projector, screen, HDMI and USB-C adapters." },
  { name: "Pressure Washer", category: :equipment, location: "Tool Library",
    description: "Electric pressure washer for cleanup days." },
  { name: "Cargo Bike", category: :vehicle, location: "Bike Shed", capacity: 1,
    description: "Electric cargo bike for deliveries around the neighborhood." },
  { name: "Old Sound System", category: :equipment, location: "Storage", active: false,
    description: "Retired; kept for reference." }
].map do |attributes|
  Resource.find_or_initialize_by(name: attributes[:name]).tap { it.update!(attributes) }
end

if Reservation.none?
  hall, study_room, _garden, projector = resources
  tomorrow = Time.current.utc.tomorrow.beginning_of_day

  [
    { user: member, resource: study_room, starts_at: tomorrow + 10.hours, ends_at: tomorrow + 12.hours,
      notes: "Group study session" },
    { user: neighbor, resource: study_room, starts_at: tomorrow + 13.hours, ends_at: tomorrow + 15.hours },
    { user: neighbor, resource: hall, starts_at: tomorrow + 1.day + 17.hours, ends_at: tomorrow + 1.day + 21.hours,
      notes: "Neighborhood potluck" },
    { user: member, resource: projector, starts_at: tomorrow + 2.days + 9.hours, ends_at: tomorrow + 2.days + 11.hours }
  ].each { Reservation.create!(it) }
end

puts "Seeded #{User.count} users, #{Resource.count} resources, #{Reservation.count} reservations."
