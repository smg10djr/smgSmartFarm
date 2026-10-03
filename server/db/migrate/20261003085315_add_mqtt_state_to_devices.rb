class AddMqttStateToDevices < ActiveRecord::Migration[8.1]
  def change
    add_column :devices, :mqtt_state, :string
  end
end
