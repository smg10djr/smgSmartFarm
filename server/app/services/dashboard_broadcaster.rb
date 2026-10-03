# 새 측정값이 저장되면 열려 있는 대시보드 화면을 새로고침 없이 갱신한다.
class DashboardBroadcaster
  STREAM = "dashboard".freeze

  def self.call(device)
    Turbo::StreamsChannel.broadcast_replace_to(
      STREAM, target: ActionView::RecordIdentifier.dom_id(device),
      partial: "dashboard/device", locals: { device: device }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      STREAM, target: "alerts", partial: "dashboard/alerts",
      locals: { alerts: AlertEvent.includes(:device).recent }
    )
  end
end
