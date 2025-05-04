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
  Creates a log line for a device.

  ## Examples

      iex> create!(device, %{level: :info, message: "Hello", meta: %{}, logged_at: NaiveDateTime.utc_now()})
      %LogLine{}

  """
  @spec create!(Device.t(), log_line_payload) :: LogLine.t()
  def create!(%Device{} = device, attrs) do
    device
    |> LogLine.create(attrs)
    |> Repo.insert!()
  end

  @spec truncate(pos_integer()) :: {:ok, non_neg_integer()}
  def truncate(days_to_keep) do
    days_ago = NaiveDateTime.shift(NaiveDateTime.utc_now(), day: -days_to_keep)

    {count, _} =
      LogLine
      |> where([ll], ll.logged_at < ^days_ago)
      |> Repo.delete_all()

    {:ok, count}
  end
end
