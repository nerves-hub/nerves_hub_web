defmodule NervesHub.Devices.LogLines do
  @moduledoc """
  Device logging storage and querying.
  """

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.LogLine

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
  @spec async_create(Device.t(), log_line_payload) ::
          {:ok, LogLine.t()} | {:error, Ecto.Changeset.t()}
  def async_create(%Device{} = device, attrs) do
    changeset = LogLine.create_changeset(device, attrs)

    case Ecto.Changeset.apply_action(changeset, :create) do
      {:ok, log_line} ->
        _ = AnalyticsRepo.insert_all(LogLine, [changeset.changes], settings: [async_insert: 1])

        _ =
          Phoenix.Channel.Server.broadcast(
            NervesHub.PubSub,
            "device:#{device.identifier}:internal",
            "logs:received",
            log_line
          )

        {:ok, log_line}

      error ->
        error
    end
  end
end
