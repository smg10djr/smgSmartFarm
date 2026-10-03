class CreateManualMeasurements < ActiveRecord::Migration[8.1]
  def change
    create_table :manual_measurements do |t|
      t.references :device, null: false, foreign_key: true
      t.datetime :measured_at, null: false
      t.decimal :ph, precision: 4, scale: 2
      t.decimal :ec_ms_cm, precision: 5, scale: 2
      t.string :note

      t.timestamps
    end
  end
end
