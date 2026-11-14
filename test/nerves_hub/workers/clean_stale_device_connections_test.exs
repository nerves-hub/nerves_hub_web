defmodule NervesHub.Workers.CleanStaleDeviceConnectionsTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias NervesHub.Devices.Connections
  alias NervesHub.Workers.CleanStaleDeviceConnections

  describe "perform/1" do
    test "calls Connections.clean_stale_connections" do
      test_pid = self()

      stub(Connections, :clean_stale_connections, fn ->
        send(test_pid, :clean_called)
        :ok
      end)

      # The ClickHouse pass runs hourly from its own worker.
      reject(&Connections.clean_stale_connections_from_analytics/0)

      job = %Oban.Job{id: Ecto.UUID.generate(), attempt: 1, args: %{}}
      assert :ok = CleanStaleDeviceConnections.perform(job)

      assert_receive :clean_called, 500
    end
  end
end
