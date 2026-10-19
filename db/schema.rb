# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_19_000003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"

  create_table "reservations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "resource_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.string "status", default: "confirmed", null: false
    t.text "notes"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_id", "starts_at"], name: "index_reservations_on_resource_id_and_starts_at"
    t.index ["resource_id"], name: "index_reservations_on_resource_id"
    t.index ["user_id", "starts_at"], name: "index_reservations_on_user_id_and_starts_at"
    t.index ["user_id"], name: "index_reservations_on_user_id"
    t.check_constraint "ends_at > starts_at", name: "reservations_ends_after_starts"
    t.check_constraint "status::text = ANY (ARRAY['confirmed'::character varying, 'cancelled'::character varying]::text[])", name: "reservations_status_allowed"
    t.exclusion_constraint "resource_id WITH =, tsrange(starts_at, ends_at, '[)'::text) WITH &&", where: "(status)::text = 'confirmed'::text", using: :gist, name: "reservations_no_overlap"
  end

  create_table "resources", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "category", null: false
    t.string "location"
    t.integer "capacity"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "category"], name: "index_resources_on_active_and_category"
    t.index ["name"], name: "index_resources_on_name", unique: true
    t.check_constraint "capacity IS NULL OR capacity > 0", name: "resources_capacity_positive"
    t.check_constraint "category::text = ANY (ARRAY['room'::character varying, 'equipment'::character varying, 'space'::character varying, 'vehicle'::character varying]::text[])", name: "resources_category_allowed"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.check_constraint "role::text = ANY (ARRAY['member'::character varying, 'admin'::character varying]::text[])", name: "users_role_allowed"
  end

  add_foreign_key "reservations", "resources"
  add_foreign_key "reservations", "users"
end
