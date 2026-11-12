defmodule NervesHubWeb.Components.UpdateProgress do
  @moduledoc """
  A firmware update the device is part way through, as the device page shows
  it: a line along the top of the device header, a badge on the header's
  firmware fact, and a panel on the Details tab's Firmware updates card.

  Stages are the strings progress reports carry (see
  `NervesHub.Devices.InflightUpdate`), from the request being sent to the
  device rebooting into the new firmware. fwup calls writing the firmware
  "updating"; it's shown as installing.
  """

  use NervesHubWeb, :component

  alias NervesHub.Devices.InflightUpdate

  @updating_stages Enum.map(InflightUpdate.active_statuses(), &to_string/1)

  attr(:stage, :string, required: true)
  attr(:progress, :any, required: true)
  attr(:class, :any, default: nil)

  @doc "The 2px line along the top of the device header, drawn as far as the update has got."
  def line(assigns) do
    assigns = assign(assigns, :percent, percent(assigns.stage, assigns.progress))

    ~H"""
    <div class={["pointer-events-none h-0.5", @class]} aria-hidden="true">
      <div class="h-0.5 bg-primary transition-[width] light:bg-indigo-600" style={"width: #{@percent}%"}></div>
    </div>
    """
  end

  @doc """
  Whether `stage` is one of an update still under way. Being ignored or
  rescheduled by the device, failing and expiring all end one.
  """
  @spec updating?(String.t() | nil) :: boolean()
  def updating?(stage), do: stage in @updating_stages

  @doc ~S"""
  Where the update has got to, for the Details tab's panel: "Downloading · 42%".
  """
  @spec phase(String.t(), integer() | nil) :: String.t()
  def phase("downloading", progress) when is_integer(progress), do: "Downloading · #{progress}%"
  def phase("updating", progress) when is_integer(progress), do: "Installing · #{progress}%"
  def phase("completed", _progress), do: "Installed · rebooting"
  def phase(stage, _progress), do: short_phase(stage, nil)

  @doc ~S"""
  The same, short enough for the badge on the header's firmware fact:
  "Downloading 42%".
  """
  @spec short_phase(String.t(), integer() | nil) :: String.t()
  def short_phase("requested", _progress), do: "Waiting for device"
  def short_phase(stage, _progress) when stage in ["received", "started"], do: "Starting"
  def short_phase("downloading", progress) when is_integer(progress), do: "Downloading #{progress}%"
  def short_phase("downloading", _progress), do: "Downloading"
  def short_phase("updating", progress) when is_integer(progress), do: "Installing #{progress}%"
  def short_phase("updating", _progress), do: "Installing"
  def short_phase("completed", _progress), do: "Rebooting"

  @doc "What the device does once the current stage is done, if anything."
  @spec next_step(String.t()) :: String.t() | nil
  def next_step(stage) when stage in ["requested", "received", "started", "downloading"],
    do: "Then installs and reboots"

  def next_step("updating"), do: "Then reboots"
  def next_step(_stage), do: nil

  @doc "How far along the progress bars are drawn, 0 to 100."
  @spec percent(String.t(), integer() | nil) :: 0..100
  def percent(stage, progress) when stage in ["downloading", "updating"] and is_integer(progress),
    do: progress |> max(0) |> min(100)

  def percent("completed", _progress), do: 100
  def percent(_stage, _progress), do: 0
end
