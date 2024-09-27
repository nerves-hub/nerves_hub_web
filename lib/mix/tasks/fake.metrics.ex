if Mix.env() == :dev do
  defmodule Mix.Tasks.Fake.Metrics do
    use Mix.Task

    alias NervesHub.Repo
    alias NervesHub.Devices.DeviceMetric

    @shortdoc "Create randomized metrics for device"
    @requirements ["app.start"]

    @impl Mix.Task
    def run([device_id | _]) do
      now = DateTime.now!("Etc/UTC") |> DateTime.truncate(:millisecond)
      a_week_ago = DateTime.add(now, -7, :day) |> DateTime.truncate(:millisecond)

      device_id
      |> String.to_integer()
      |> add_metrics(now, a_week_ago)
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
        "load_15min" => :rand.uniform(),
        "load_1min" => :rand.uniform(),
        "load_5min" => :rand.uniform(),
        "size_mb" => 7892,
        "used_mb" => Enum.random(0..7892),
        "used_percent" => Enum.random(0..100)
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
end
