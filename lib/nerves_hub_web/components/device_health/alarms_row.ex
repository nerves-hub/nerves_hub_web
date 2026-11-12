defmodule NervesHubWeb.Components.DeviceHealth.AlarmsRow do
  @moduledoc """
  The row of a device's active alarms at the foot of a health card, on the
  Details tab's Health card and the Health tab's Now card: a count, then each
  alarm on its own line with its description and when it was raised under it.
  """

  use NervesHubWeb, :component

  attr(:id, :string, required: true)

  attr(:alarms, :any,
    required: true,
    doc: "`NervesHub.Devices.Alarms.current_alarms_for_device/1`: `[{alarm, description, raised_at}]`, or nil"
  )

  attr(:time_zone, :string, default: "UTC")

  def render(assigns) do
    ~H"""
    <div class="px-4">
      <div id={@id} class="flex flex-col gap-2.5 border-t border-line-subtle pt-3 pb-3.5 text-ui/4">
        <div class="flex items-center gap-2.5">
          <span class={["lucide-bell size-3.75", if(@alarms, do: "text-warning", else: "text-content-faint")]} aria-hidden="true"></span>
          <span class="font-medium text-content-body">Alarms</span>
          <span :if={!@alarms} class="text-content-muted">None active</span>
          <span :if={@alarms} class="font-medium text-warning-content">{Enum.count(@alarms)} active</span>
        </div>
        <ul :if={@alarms} class="flex flex-col gap-1.5 pl-6.25">
          <li
            :for={{alarm, description, raised_at} <- @alarms}
            class="flex min-w-0 flex-col gap-0.5 rounded border border-l-2 border-line-default border-l-warning bg-surface-muted px-2.5 py-1.5"
          >
            <code class="font-mono text-xs/4 font-semibold break-all text-content-strong">{alarm}</code>
            <span :if={description?(description)} class="font-mono text-xs/4 break-all text-content-muted">{description}</span>
            <span class="font-mono text-xs/4 text-content-muted">
              since <.local_datetime at={raised_at} time_zone={@time_zone} format={since_format(raised_at, @time_zone)} zone_label={false} />
            </span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  # The time alone for an alarm raised today, which most are; the date as
  # well once it has been up since an earlier day.
  defp since_format(raised_at, time_zone) do
    if day_label(raised_at, time_zone) == "Today", do: :time, else: :short_datetime
  end

  defp description?(description) do
    is_binary(description) and byte_size(description) > 0 and description != "[]"
  end
end
