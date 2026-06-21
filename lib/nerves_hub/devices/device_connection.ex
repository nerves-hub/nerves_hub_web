defmodule NervesHub.Devices.DeviceConnection do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Devices.Device
  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}
  @primary_key {:id, UUIDv7, autogenerate: true}

  schema "latest_device_connections" do
    belongs_to(:org, Org)
    belongs_to(:product, Product)
    belongs_to(:device, Device)

    field(:established_at, :utc_datetime_usec)
    field(:last_seen_at, :utc_datetime_usec)
    field(:disconnected_at, :utc_datetime_usec)

    field(:disconnected_reason, :string)

    field(:metadata, :map, default: %{})

    field(:status, Ecto.Enum,
      values: [:connecting, :connected, :disconnected],
      default: :connecting
    )

    field(:lib, :string)
    field(:lib_version, :string)

    field(:network_interface, Ecto.Enum, values: [:wifi, :ethernet, :cellular, :unknown])
  end

  def connecting_changeset(org_id, product_id, device_id) do
    now = DateTime.utc_now()

    %__MODULE__{}
    |> change()
    |> put_change(:org_id, org_id)
    |> put_change(:product_id, product_id)
    |> put_change(:device_id, device_id)
    |> put_change(:established_at, now)
    |> put_change(:last_seen_at, now)
    |> put_change(:status, :connecting)
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
end
