class CreateAlertEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :alert_events do |t|
      t.references :device, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :message, null: false
      t.datetime :triggered_at, null: false
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :alert_events, [ :device_id, :kind ], unique: true, where: "resolved_at IS NULL", name: "index_alert_events_one_open_per_kind"
  end
end
