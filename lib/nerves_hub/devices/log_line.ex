defmodule NervesHub.Devices.LogLine do
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

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
      |> Map.put("device_id", device.id)
      |> Map.put("product_id", device.product_id)
      |> maybe_set_timestamp()
      |> format_message()

    %__MODULE__{}
    |> cast(params, @required ++ @optional)
    |> validate_required(@required)
  end

  defp maybe_set_timestamp(%{"timestamp" => _} = params), do: params

  defp maybe_set_timestamp(params) do
    {:ok, timestamp} =
      params["meta"]["time"]
      |> String.to_integer()
      |> DateTime.from_unix(:microsecond)

    Map.put(params, "timestamp", timestamp)
  end

  defp format_message(%{"message" => message} = params) when is_binary(message), do: params

  defp format_message(%{"message" => message} = params) when is_list(message) do
    Map.put(params, "message", List.to_string(message))
  end

  defp format_message(%{"message" => message} = params) do
    Map.put(params, "message", inspect(message))
  end
end
