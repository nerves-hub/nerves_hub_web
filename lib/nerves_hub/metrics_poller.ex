defmodule NervesHub.MetricsPoller do
  def child_spec() do
    {:telemetry_poller,
     measurements: [
       {NervesHub.MetricsPoller, :report_device_count, []}
     ],
     period: to_timeout(minute: 1),
     name: :nerves_hub_poller}
  end

  def report_device_count() do
    # an ugly way to get the connected device count for a node
    # (we can't use the device registry because it's been removed)
    #
    # Ask for the dictionary alone. `Process.info/1` returns sixteen items --
    # including `links` and the `garbage_collection` keyword list -- and copies
    # all of them into this process. On a node holding a device channel per
    # device that ran to millions of terms allocated here every minute, and a
    # process heap that stays inflated until it happens to full-sweep.
    device_count =
      Enum.count(Process.list(), fn pid ->
        case Process.info(pid, :dictionary) do
          {:dictionary, dictionary} ->
            dictionary[:"$initial_call"] == {NervesHubWeb.DeviceChannel, :join, 3}

          # the process exited while we were walking the list
          nil ->
            false
        end
      end)

    :telemetry.execute([:nerves_hub, :devices, :online], %{count: device_count}, %{node: node()})
  end
end
