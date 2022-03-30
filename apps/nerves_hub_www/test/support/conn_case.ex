defmodule NervesHubWWWWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
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
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest, except: [init_test_session: 2]

      alias NervesHubWWWWeb.Router.Helpers, as: Routes

      # The default endpoint for testing
      @endpoint NervesHubWWWWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(NervesHubWebCore.Repo)

    unless tags[:async] do
      pid =
        Ecto.Adapters.SQL.Sandbox.start_owner!(NervesHubWebCore.Repo, shared: not tags[:async])

      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
