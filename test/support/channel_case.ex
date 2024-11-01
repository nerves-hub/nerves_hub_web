defmodule NervesHubWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier
  to build common datastructures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      use DefaultMocks
      use Oban.Testing, repo: NervesHub.ObanRepo

      # The default endpoint for testing
      @endpoint NervesHubWeb.DeviceEndpoint
    end
  end

  setup do
    # Explicitly get a connection before each test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(NervesHub.Repo)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(NervesHub.ObanRepo)
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(NervesHub.Repo, shared: not tags[:async])
    pid2 = Ecto.Adapters.SQL.Sandbox.start_owner!(NervesHub.ObanRepo, shared: not tags[:async])

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid2)
    end)

    :ok
  end
end
