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

ActiveRecord::Schema[8.1].define(version: 2026_10_03_084128) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "devices", force: :cascade do |t|
    t.string "device_id"
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_devices_on_device_id", unique: true
  end

  create_table "sensor_readings", force: :cascade do |t|
    t.bigint "device_id", null: false
    t.datetime "measured_at", null: false
    t.integer "sequence"
    t.decimal "air_temperature_c", precision: 5, scale: 2
    t.decimal "humidity_pct", precision: 5, scale: 2
    t.decimal "water_temperature_c", precision: 5, scale: 2
    t.integer "illuminance_lux"
    t.boolean "water_low"
    t.jsonb "raw", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id", "measured_at"], name: "index_sensor_readings_on_device_id_and_measured_at", unique: true
    t.index ["device_id"], name: "index_sensor_readings_on_device_id"
  end

  add_foreign_key "sensor_readings", "devices"
end
