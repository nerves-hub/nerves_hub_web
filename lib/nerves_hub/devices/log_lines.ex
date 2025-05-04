defmodule NervesHub.Devices.LogLines do
  @moduledoc """
  Device logging storage and querying.
  """

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.LogLine
  alias NervesHub.Repo

  import Ecto.Query

  @type log_line_payload :: %{
          level: String.t(),
          message: String.t(),
          meta: map(),
          logged_at: NaiveDateTime.t()
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
    |> where(device_id: ^device.id)
    |> order_by(desc: :id)
    |> limit(25)
    |> Repo.all()
  end

  @doc """
  Inserts a one log line for a device.

  ## Examples

      iex> insert(device, %{level: :info, message: "Hello", meta: %{}, logged_at: NaiveDateTime.utc_now()})
      %LogLine{}

  """
  @spec insert(Device.t(), log_line_payload) :: LogLine.t()
  def insert(%Device{} = device, attrs) do
    device
    |> LogLine.create(attrs)
    |> Repo.insert!()
  end
end
