defmodule NervesHub.Devices.DisconnectReason do
  @moduledoc """
  Why a device's connection ended, as recorded in
  `latest_device_connections.disconnected_reason` and copied into
  `device_connection_history`.

    * `:light_sleep`, `:deep_sleep` — the device said it was going to sleep
      (the `sleeping` message), usually with when it expects to wake
    * `:rebooting` — the device said it was rebooting
    * `:stale_connection` — the device stopped sending heartbeats, and the
      sweep closed the connection
    * `:duplicate_connection` — the device connected again while this
      connection was still open, and the new one replaced it (see
      `NervesHub.Devices.Connections.device_connecting/5`)
    * `:reconnect_requested` — someone asked the device to reconnect, from the
      web UI or the API
    * `:key_revoked` — the shared secret key the device authenticated with was
      deactivated
    * `:platform_update` — the node holding the connection shut down, as it
      does during a deploy

  `nil` means the connection closed without NervesHub knowing why.

  A reason the device announced is written when it announces it, before the
  socket closes, and nothing written after replaces it: see
  `NervesHub.Devices.Connections.device_leaving/3`.

  Stored as a string rather than a Postgres enum, so adding a reason needs no
  migration. Loading is lenient: a string this version does not know loads as
  `nil` rather than raising, which a rolling deploy needs, since the previous
  release writes values this one may not list. Releases before the enum
  wrote `"Stale connection"` and `"Reconnected"`, which still load as
  `:stale_connection` and `:duplicate_connection`.
  """

  use Ecto.Type

  @type sleep() :: :light_sleep | :deep_sleep

  @type planned() :: sleep() | :rebooting | :reconnect_requested | :key_revoked | :platform_update

  @type t() :: planned() | :stale_connection | :duplicate_connection

  @values [
    :light_sleep,
    :deep_sleep,
    :rebooting,
    :stale_connection,
    :duplicate_connection,
    :reconnect_requested,
    :key_revoked,
    :platform_update
  ]

  @sleep [:light_sleep, :deep_sleep]

  # Disconnects that were meant to happen, by the device or by an operator or
  # the platform, rather than the connection failing.
  @planned @sleep ++ [:rebooting, :reconnect_requested, :key_revoked, :platform_update]

  @by_string Map.new(@values, &{Atom.to_string(&1), &1})

  # Written by releases before the reason was an enum.
  @legacy %{"Stale connection" => :stale_connection, "Reconnected" => :duplicate_connection}

  @doc "Every reason, in the order above."
  @spec values() :: nonempty_list(t())
  def values(), do: @values

  @doc "The reasons that mean the device went to sleep."
  @spec sleep_values() :: nonempty_list(sleep())
  def sleep_values(), do: @sleep

  @doc """
  The reasons that mean the disconnect was planned, so it says nothing about
  the device's connectivity. The flapping and "disconnects" health counts leave
  these out.
  """
  @spec planned_values() :: nonempty_list(planned())
  def planned_values(), do: @planned

  @doc "Whether `reason` means the device went to sleep."
  @spec sleep?(t() | nil) :: boolean()
  def sleep?(reason), do: reason in @sleep

  @doc """
  A short description for people, as the web UI and the `reason` field of the
  `device.disconnected` webhook show it.

  `:stale_connection` and `:duplicate_connection` keep the text releases
  before the enum sent, which webhook receivers may already match on.
  """
  @spec label(t() | nil) :: String.t() | nil
  def label(nil), do: nil
  def label(:light_sleep), do: "Light sleep"
  def label(:deep_sleep), do: "Deep sleep"
  def label(:rebooting), do: "Rebooting"
  def label(:stale_connection), do: "Stale connection"
  def label(:duplicate_connection), do: "Reconnected"
  def label(:reconnect_requested), do: "Reconnect requested"
  def label(:key_revoked), do: "Device key deactivated"
  def label(:platform_update), do: "Server restarted"

  @impl Ecto.Type
  def type(), do: :string

  @impl Ecto.Type
  def cast(reason) when reason in @values, do: {:ok, reason}
  def cast(reason) when is_binary(reason), do: Map.fetch(@by_string, reason)
  def cast(_reason), do: :error

  @impl Ecto.Type
  def load(reason) when is_binary(reason) do
    {:ok, Map.get(@by_string, reason) || Map.get(@legacy, reason)}
  end

  @impl Ecto.Type
  def dump(reason) when reason in @values, do: {:ok, Atom.to_string(reason)}
  def dump(_reason), do: :error
end
