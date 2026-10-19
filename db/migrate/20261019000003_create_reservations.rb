class CreateReservations < ActiveRecord::Migration[8.1]
  def change
    # btree_gist lets a GiST index combine plain equality (resource_id) with
    # range overlap (&&), which the exclusion constraint below needs.
    enable_extension "btree_gist"

    create_table :reservations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :resource, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :status, null: false, default: "confirmed"
      t.text :notes
      t.datetime :cancelled_at

      t.timestamps
    end

    add_index :reservations, [ :resource_id, :starts_at ]
    add_index :reservations, [ :user_id, :starts_at ]

    add_check_constraint :reservations, "ends_at > starts_at", name: "reservations_ends_after_starts"
    add_check_constraint :reservations, "status IN ('confirmed', 'cancelled')", name: "reservations_status_allowed"

    # Concurrency protection: two confirmed reservations for the same resource can
    # never overlap, even if two requests pass model validation at the same moment.
    # '[)' bounds make back-to-back bookings (10:00-11:00 then 11:00-12:00) legal.
    add_exclusion_constraint :reservations,
      "resource_id WITH =, tsrange(starts_at, ends_at, '[)') WITH &&",
      using: :gist,
      where: "status = 'confirmed'",
      name: "reservations_no_overlap"
  end
end
