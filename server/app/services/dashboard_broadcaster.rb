# 새 측정값·상태·알림이 저장되면 열려 있는 대시보드를 새로고침 없이 갱신한다.
# 장치 카드는 컨테이너(#devices)째로 갱신해서, 첫 장치가 생기는 순간에도 화면에 나타난다.
class DashboardBroadcaster
  STREAM = "dashboard".freeze

  def self.call(_device = nil)
    devices = Device.order(:device_id)

    update("devices", "dashboard/devices", devices: devices)
    update("manual-section", "dashboard/manual_form", devices: devices)
    update("alerts", "dashboard/alerts", alerts: AlertEvent.includes(:device).recent)
  end

  def self.update(target, partial, locals)
    Turbo::StreamsChannel.broadcast_replace_to(STREAM, target: target, partial: partial, locals: locals)
  end
  private_class_method :update
end
