defmodule NervesHub.Workers.CleanStaleDeviceConnectionHistoryTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias NervesHub.Devices.Connections
  alias NervesHub.Workers.CleanStaleDeviceConnectionHistory

  describe "perform/1" do
    test "calls Connections.clean_stale_connections_from_analytics" do
      test_pid = self()

      stub(Connections, :clean_stale_connections_from_analytics, fn ->
        send(test_pid, :analytics_clean_called)
        :ok
      end)

      reject(&Connections.clean_stale_connections/0)

      job = %Oban.Job{id: Ecto.UUID.generate(), attempt: 1, args: %{}}
      assert :ok = CleanStaleDeviceConnectionHistory.perform(job)

      assert_receive :analytics_clean_called, 500
    end
  end
end
