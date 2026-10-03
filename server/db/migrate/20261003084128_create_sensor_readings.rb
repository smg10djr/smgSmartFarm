class CreateSensorReadings < ActiveRecord::Migration[8.1]
  def change
    create_table :sensor_readings do |t|
      t.references :device, null: false, foreign_key: true
      t.datetime :measured_at, null: false
      t.integer :sequence
      t.decimal :air_temperature_c, precision: 5, scale: 2
      t.decimal :humidity_pct, precision: 5, scale: 2
      t.decimal :water_temperature_c, precision: 5, scale: 2
      t.integer :illuminance_lux
      t.boolean :water_low
      t.jsonb :raw, null: false, default: {}

      t.timestamps
    end

    add_index :sensor_readings, [ :device_id, :measured_at ], unique: true
  end
end
