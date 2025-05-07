defmodule NervesHub.Devices.LogLine do
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @primary_key false

  @required [:device_id, :product_id, :timestamp, :level, :message]
  @optional [:meta]

  @primary_key false
  schema "device_log_lines" do
    field(:timestamp, Ch, type: "DateTime64(6, 'UTC')")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")
    field(:level, Ch, type: "LowCardinality(String)")
    field(:message, Ch, type: "String")
    field(:meta, Ch, type: "Map(LowCardinality(String), String)", default: %{})
  end

  def create(device, params \\ %{}) do
    params =
      params
      |> Map.put(:device_id, device.id)
      |> Map.put(:product_id, device.product_id)

    %__MODULE__{}
    |> cast(params, @required ++ @optional)
    |> validate_required(@required)
  end
end
