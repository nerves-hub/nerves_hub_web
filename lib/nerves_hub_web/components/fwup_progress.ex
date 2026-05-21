defmodule NervesHubWeb.Components.FwupProgress do
  use NervesHubWeb, :component

  attr(:progress, :any)
  attr(:stage, :any)

  def render(assigns) do
    assigns = assign(assigns, :stage, to_string(assigns.stage))

    assigns =
      if assigns.stage in ["downloading", "updating"] do
        assigns
      else
        assign(assigns, :progress, 100)
      end

    message =
      case assigns.stage do
        "requested" ->
          "Firmware update request sent to the device"

        "received" ->
          "Firmware update request received by the device"

        "started" ->
          "Firmware update started..."

        stage when stage in ["downloading", "updating"] ->
          "#{String.capitalize(assigns.stage)} firmware : #{assigns.progress}%"

        "completed" ->
          "Firmware update complete, waiting for device to restart"

        "expired" ->
          "Firmware update aborted - no updates received"

        _ ->
          ""
      end

    assigns = assign(assigns, :message, message)

    ~H"""
    <div class="relative -top-[11px] z-100 flex h-0 w-full justify-center">
      <div class="bg-surface-muted border-base-700 h-[24px] rounded-full border px-2.5 py-0.5 text-[0.8rem] font-normal">{@message}</div>
    </div>
    <div class="sticky top-0 z-20 h-0 w-full overflow-visible">
      <div class="border-success absolute z-40 border-t" role="progressbar" style={"width: #{@progress}%"}>
        <div class="progress-glow h-16 w-full animate-pulse" />
      </div>
    </div>
    """
  end
end
