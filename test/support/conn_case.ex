defmodule NervesHubWeb.ConnCase do
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

      alias NervesHubWeb.Router.Helpers, as: Routes

      # The default endpoint for testing
      @endpoint NervesHubWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(NervesHub.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(NervesHub.Repo, {:shared, self()})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end

defmodule NervesHubWeb.APIConnCase do
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
  alias NervesHub.Fixtures

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest

      use DefaultMocks
      import NervesHubWeb.APIConnCase, only: [build_auth_conn: 1]

      alias NervesHubWeb.APIRouter.Helpers, as: Routes

      # The default endpoint for testing
      @endpoint NervesHubWeb.API.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(NervesHub.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(NervesHub.Repo, {:shared, self()})
    end

    user = Fixtures.user_fixture()
    {:ok, token} = NervesHub.Accounts.create_user_token(user, "test-token")

    user2 = Fixtures.user_fixture(%{username: user.username <> "0"})
    {:ok, token2} = NervesHub.Accounts.create_user_token(user2, "test-token")

    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org, %{name: "starter"})

    {:ok,
     conn: build_auth_conn(token.token),
     conn2: build_auth_conn(token2.token),
     org: org,
     user: user,
     user_token: token,
     user2: user2,
     user2_token: token2,
     product: product}
  end

  def build_auth_conn(token) do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("authorization", "token #{token}")
    |> Plug.Conn.put_req_header("accept", "application/json")
  end
end
