defmodule NervesHub.Devices.LogLines do
  @moduledoc """
  Device logging storage and querying.
  """

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.LogLine
  alias NervesHub.AnalyticsRepo

  import Ecto.Query

  @type log_line_payload :: %{
          timestamp: DateTime.t(),
          level: String.t(),
          message: String.t(),
          meta: map()
        }

  @doc """
  Retrieves the most recent 25 log lines for a device.

  ## Examples

      iex> recent(device)
      [%LogLine{}, %LogLine{}]

  """
  @spec recent(Device.t()) :: list(LogLine.t())
  def recent(device) do
    LogLine
    |> where(product_id: ^device.product_id)
    |> where(device_id: ^device.id)
    |> order_by(desc: :timestamp)
    |> limit(25)
    |> AnalyticsRepo.all()
  end

  @doc """
  Creates a log line for a device.

  ## Examples

      iex> create!(device, %{level: :info, message: "Hello", meta: %{}, timestamp: DateTime.utc_now()})
      %LogLine{}

  """
  @spec create!(Device.t(), log_line_payload) :: LogLine.t()
  def create!(%Device{} = device, attrs) do
    device
    |> LogLine.create(attrs)
    |> AnalyticsRepo.insert!()
    |> then(fn log_line ->
      _ =
        Phoenix.Channel.Server.broadcast(
          NervesHub.PubSub,
          "device:#{device.identifier}:internal",
          "logs:received",
          log_line
        )

      log_line
    end)
  end
end
