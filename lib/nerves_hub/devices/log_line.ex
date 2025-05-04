defmodule NervesHub.Devices.LogLine do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device
  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}
  @primary_key {:id, UUIDv7, autogenerate: true}

  @required [:device_id, :product_id, :level, :message, :logged_at]
  @optional [:meta]

  schema "device_log_lines" do
    belongs_to(:device, Device)
    belongs_to(:product, Product)

    field(:level, Ecto.Enum, values: [:debug, :info, :warning, :error], default: :info)
    field(:message, :string)
    field(:meta, :map, default: %{})

    field(:logged_at, :naive_datetime_usec)
  end

  def create(device, params \\ %{}) do
    params =
      params
      |> Map.put(:device_id, device.id)
      |> Map.put(:product_id, device.product_id)

    %__MODULE__{}
    |> cast(params, @required ++ @optional)
    |> validate_required(@required)
    |> foreign_key_constraint(:device_id)
  end
end
