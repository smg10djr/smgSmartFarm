class CreateDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :devices do |t|
      t.string :device_id
      t.datetime :last_seen_at

      t.timestamps
    end
    add_index :devices, :device_id, unique: true
  end
end
