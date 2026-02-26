defmodule NervesHubWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox, as: SQLSandbox

  using do
    quote do
      use DefaultMocks
      use Oban.Testing, repo: NervesHub.Repo
      use AssertEventually, timeout: 500, interval: 50

      import Ecto.Query
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest

      alias NervesHub.Devices.DeviceConnection

      # The default endpoint for testing
      @endpoint NervesHubWeb.DeviceEndpoint

      def subscribe_device_internal(device) do
        Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}:internal")
      end

      def subscribe_extensions(device) do
        Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}:extensions")
      end

      def assert_online_and_available(device) do
        device_connection_query =
          DeviceConnection
          |> where(status: :connected)
          |> where(device_id: ^device.id)

        eventually(assert(NervesHub.Repo.exists?(device_connection_query)))
      end

      def close_cleanly(channel) do
        Process.unlink(channel.channel_pid)
        :ok = close(channel)
      end
    end
  end

  setup do
    # Explicitly get a connection before each test
    :ok = SQLSandbox.checkout(NervesHub.Repo)
  end

  setup tags do
    pid = SQLSandbox.start_owner!(NervesHub.Repo, shared: not tags[:async])

    on_exit(fn ->
      SQLSandbox.stop_owner(pid)
    end)

    :ok
  end
end
