defmodule Mix.Tasks.NervesHub.Gen.Metrics do
  @moduledoc """
  Generate a collection of metrics for one or more devices.

  ## Examples

      mix nerves_hub.gen.metrics device-1234
  """

  @shortdoc "Generate metrics for one or more devices"

  use Mix.Task

  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Repo

  @requirements ["app.start"]
  @preferred_cli_env :dev

  @impl Mix.Task
  def run([device_identifier | _]) do
    {:ok, %{id: device_id}} = Devices.get_by_identifier(device_identifier)
    now = DateTime.now!("Etc/UTC") |> DateTime.truncate(:millisecond)
    a_week_ago = DateTime.add(now, -7, :day) |> DateTime.truncate(:millisecond)

    add_metrics(device_id, now, a_week_ago)
  end

  @doc """
  Runs recursively until current timestamp is less than or equal to ending timestamp
  """
  def add_metrics(device_id, current_timestamp, ending_timestamp)
      when current_timestamp <= ending_timestamp,
      do: save_metrics(device_id, current_timestamp)

  def add_metrics(device_id, current_timestamp, ending_timestamp) do
    save_metrics(device_id, current_timestamp)

    new_timestamp = DateTime.add(current_timestamp, -20, :minute)
    add_metrics(device_id, new_timestamp, ending_timestamp)
  end

  def save_metrics(device_id, current_timestamp) do
    metrics = %{
      "cpu_temp" => Enum.random(1..100),
      "load_1min" => :rand.uniform() |> Float.ceil(2),
      "load_5min" => :rand.uniform() |> Float.ceil(2),
      "load_15min" => :rand.uniform() |> Float.ceil(2),
      "mem_size_mb" => 7892,
      "mem_used_mb" => Enum.random(0..7892),
      "mem_used_percent" => Enum.random(0..100)
    }

    Repo.transaction(fn ->
      Enum.map(metrics, fn {key, val} ->
        DeviceMetric.save_with_timestamp(%{
          device_id: device_id,
          key: key,
          value: val,
          inserted_at: current_timestamp
        })
        |> Repo.insert()
      end)
    end)
  end
end
