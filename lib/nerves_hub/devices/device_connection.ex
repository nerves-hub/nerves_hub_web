defmodule NervesHub.Devices.DeviceConnection do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Devices.ClientLibrary
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DisconnectReason
  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}
  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}

  schema "latest_device_connections" do
    belongs_to(:org, Org)
    belongs_to(:product, Product)
    belongs_to(:device, Device)

    field(:established_at, :utc_datetime_usec)
    field(:last_seen_at, :utc_datetime_usec)
    field(:disconnected_at, :utc_datetime_usec)

    field(:disconnected_reason, DisconnectReason)

    # When a device that went to sleep said it would be back, and (reserved,
    # not yet set) when it was found not to be. Both are cleared when the
    # device connects again.
    field(:expected_wake_at, :utc_datetime_usec)
    field(:wake_missed_at, :utc_datetime_usec)

    field(:metadata, :map, default: %{})

    field(:status, Ecto.Enum,
      values: [:connecting, :connected, :disconnected],
      default: :connecting
    )

    field(:lib, :string)
    field(:lib_version, :string)

    field(:ip_address, :string)

    field(:network_interface, Ecto.Enum, values: [:wifi, :ethernet, :cellular, :unknown])
  end

  @doc """
  A new connection for a device, as it starts connecting.

  `client_library` is the library the device connected with, as
  `NervesHub.Devices.ClientLibrary.from_user_agent/1` reads it; leaving it out
  records the library as unknown.
  """
  @spec connecting_changeset(
          pos_integer(),
          pos_integer(),
          pos_integer(),
          String.t() | nil,
          ClientLibrary.t()
        ) :: Ecto.Changeset.t()
  def connecting_changeset(
        org_id,
        product_id,
        device_id,
        ip_address \\ nil,
        client_library \\ %{lib: nil, lib_version: nil}
      ) do
    now = DateTime.utc_now()

    %__MODULE__{}
    |> change()
    |> put_change(:org_id, org_id)
    |> put_change(:product_id, product_id)
    |> put_change(:device_id, device_id)
    |> put_change(:established_at, now)
    |> put_change(:last_seen_at, now)
    |> put_change(:status, :connecting)
    |> put_change(:ip_address, ip_address)
    |> put_change(:lib, client_library.lib)
    |> put_change(:lib_version, client_library.lib_version)
  end

  @spec humanized_network_interface_name(any()) :: :wifi | :ethernet | :cellular | :unknown
  def humanized_network_interface_name(interface) when is_binary(interface) do
    cond do
      String.starts_with?(interface, "wlan") -> :wifi
      String.starts_with?(interface, "eth") or String.starts_with?(interface, "en") -> :ethernet
      String.starts_with?(interface, "wwan") -> :cellular
      true -> :unknown
    end
  end

  def humanized_network_interface_name(_interface) do
    :unknown
  end

  # The least a sleeping device is allowed to be late by, and the share of its
  # sleep it is allowed on top. An ESP32 without a 32 kHz crystal times its
  # sleep with an RC oscillator that drifts by several percent, so a margin
  # fixed in minutes would flag long sleepers that are only as late as their
  # clock.
  @wake_margin_floor_seconds 120
  @wake_margin_share 0.1

  @doc """
  Where a connection stands with respect to sleep, at `now`.

    * `:going_to_sleep` - the device said it is going to sleep, and its
      connection has not closed yet
    * `:asleep` - it is asleep, and either not yet past `wake_deadline/1` or
      gave no time
    * `:overdue` - it is past `wake_deadline/1`: later than it said by more
      than two minutes or a tenth of how long it slept, whichever is longer
    * `nil` - the device did not say it was going to sleep
  """
  @spec sleep_state(t() | nil, DateTime.t()) :: :going_to_sleep | :asleep | :overdue | nil
  def sleep_state(connection, now \\ DateTime.utc_now())

  def sleep_state(%__MODULE__{disconnected_reason: reason} = connection, now) do
    cond do
      not DisconnectReason.sleep?(reason) -> nil
      connection.status != :disconnected -> :going_to_sleep
      overdue?(connection, now) -> :overdue
      true -> :asleep
    end
  end

  def sleep_state(_connection, _now), do: nil

  @doc """
  When a sleeping device counts as overdue: its expected wake plus the margin
  `sleep_state/2` allows. `nil` when it gave no time.
  """
  @spec wake_deadline(t()) :: DateTime.t() | nil
  def wake_deadline(%__MODULE__{expected_wake_at: nil}), do: nil

  def wake_deadline(%__MODULE__{expected_wake_at: expected, disconnected_at: slept_at}) do
    slept_for = if slept_at, do: max(DateTime.diff(expected, slept_at), 0), else: 0
    margin = max(@wake_margin_floor_seconds, round(slept_for * @wake_margin_share))

    DateTime.add(expected, margin, :second)
  end

  defp overdue?(connection, now) do
    case wake_deadline(connection) do
      nil -> false
      deadline -> DateTime.after?(now, deadline)
    end
  end
end
