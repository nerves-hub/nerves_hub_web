defmodule NervesHubWeb.Components.FwupProgress do
  use NervesHubWeb, :component

  attr(:progress, :any)
  attr(:stage, :any)

  def render(assigns) do
    assigns =
      assigns
      |> assign(:stage, to_string(assigns.stage))
      |> assign_progress()
      |> assign_message()

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

  defp assign_message(assigns) do
    assign(assigns, :message, format_message(assigns))
  end

  defp format_message(%{stage: "requested"}), do: "Firmware update request sent to the device"
  defp format_message(%{stage: "rescheduled"}), do: "The device has requested firmware updates be delayed"
  defp format_message(%{stage: "ignored"}), do: "The device has ignored the firmware update request"
  defp format_message(%{stage: "received"}), do: "Firmware update request received by the device"
  defp format_message(%{stage: "started"}), do: "Firmware update started..."
  defp format_message(%{stage: "completed"}), do: "Firmware update complete, waiting for device to restart"
  defp format_message(%{stage: "expired"}), do: "Firmware update aborted - no updates received"
  defp format_message(%{stage: stage, progress: progress}), do: "#{String.capitalize(stage)} firmware : #{progress}%"

  defp assign_progress(assigns) do
    if assigns.stage in ["downloading", "updating"] do
      assigns
    else
      assign(assigns, :progress, 100)
    end
  end
end
