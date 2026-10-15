defmodule NervesHub.Webhooks.Events do
  @moduledoc """
  The events a product webhook can subscribe to.

  Each type is the `type` field of the delivered payload, and the name a
  receiver switches on. Types follow the Standard Webhooks convention:
  dot-separated, with each part made of letters, digits and underscores.

  **The type names and the shape of each event's `data` are a published
  contract.** Receivers are written against them in code this repository
  cannot see. Adding a type, or a key to an event's `data`, is safe; renaming
  or removing either breaks somebody's integration. `docs/webhooks.md`
  documents each payload and must be kept in step with the builders in
  `NervesHub.Webhooks`.
  """

  @typedoc "One subscribable event, as the settings page describes it."
  @type event() :: %{type: String.t(), group: String.t(), label: String.t(), description: String.t()}

  @events [
    %{
      type: "device.connected",
      group: "Connection",
      label: "Device connected",
      description: "A device finished connecting and is online."
    },
    %{
      type: "device.disconnected",
      group: "Connection",
      label: "Device disconnected",
      description:
        "A device's connection closed, or was closed by NervesHub after the device stopped sending heartbeats."
    },
    %{
      type: "device.health_reported",
      group: "Health",
      label: "Health report received",
      description:
        "A device sent a health report: its metrics, alarms and metadata. Devices report every hour, and every minute while somebody has the device's page open."
    },
    %{
      type: "device.metrics_reported",
      group: "Health",
      label: "Metrics received",
      description:
        "A device sent a batch of metrics readings. Only devices using the metrics extension send these; others include their metrics in health reports."
    },
    %{
      type: "device.health_status_changed",
      group: "Health",
      label: "Health status changed",
      description:
        "A device's health status moved, such as from healthy to warning, judged against the product's health profile."
    },
    %{
      type: "device.firmware_update.scheduled",
      group: "Firmware",
      label: "Update sent",
      description:
        "A firmware update was sent to a device, by a deployment group, by a user, or because the device asked."
    },
    %{
      type: "device.firmware_update.progress",
      group: "Firmware",
      label: "Update progress",
      description:
        "A device reported how its update is going: received, started, downloading, updating or completed. Progress percentages are sent at most every 15 seconds."
    },
    %{
      type: "device.firmware_update.finished",
      group: "Firmware",
      label: "Update finished",
      description:
        "A device's update attempt ended. The outcome is one of succeeded, failed, ignored, rescheduled, expired or abandoned."
    },
    %{
      type: "device.firmware_validated",
      group: "Firmware",
      label: "Firmware validated",
      description: "A device confirmed that the firmware it is running is good."
    }
  ]

  @types Enum.map(@events, & &1.type)

  @test_type "webhook.test"

  @doc "Every subscribable event, in the order the settings page lists them."
  @spec all() :: [event(), ...]
  def all(), do: @events

  @doc "Every subscribable event type."
  @spec types() :: [String.t(), ...]
  def types(), do: @types

  @doc """
  The events grouped for display, as `{group, events}` in their listed order.
  """
  @spec grouped() :: [{String.t(), [event()]}]
  def grouped() do
    @events
    |> Enum.chunk_by(& &1.group)
    |> Enum.map(fn [%{group: group} | _] = events -> {group, events} end)
  end

  @doc "The human name of an event type, falling back to the type itself."
  @spec label(String.t()) :: String.t()
  def label(type) do
    case Enum.find(@events, &(&1.type == type)) do
      %{label: label} -> label
      nil -> type
    end
  end

  @doc """
  The type of the event sent by "Send test event".

  Not subscribable: it is only ever sent on request, to the one webhook being
  tested, whatever that webhook subscribes to.
  """
  @spec test_type() :: String.t()
  def test_type(), do: @test_type
end
