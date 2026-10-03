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

ActiveRecord::Schema[8.1].define(version: 2026_10_03_085316) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "alert_events", force: :cascade do |t|
    t.bigint "device_id", null: false
    t.string "kind", null: false
    t.string "message", null: false
    t.datetime "triggered_at", null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id", "kind"], name: "index_alert_events_one_open_per_kind", unique: true, where: "(resolved_at IS NULL)"
    t.index ["device_id"], name: "index_alert_events_on_device_id"
  end

  create_table "devices", force: :cascade do |t|
    t.string "device_id"
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "mqtt_state"
    t.index ["device_id"], name: "index_devices_on_device_id", unique: true
  end

  create_table "manual_measurements", force: :cascade do |t|
    t.bigint "device_id", null: false
    t.datetime "measured_at", null: false
    t.decimal "ph", precision: 4, scale: 2
    t.decimal "ec_ms_cm", precision: 5, scale: 2
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_manual_measurements_on_device_id"
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

  add_foreign_key "alert_events", "devices"
  add_foreign_key "manual_measurements", "devices"
  add_foreign_key "sensor_readings", "devices"
end
