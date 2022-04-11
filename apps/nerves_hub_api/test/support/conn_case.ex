defmodule NervesHubAPIWeb.ConnCase do
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
  alias NervesHubWebCore.Fixtures

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest

      use DefaultMocks
      import NervesHubAPIWeb.ConnCase, only: [build_auth_conn: 1, peer_data: 1]

      alias NervesHubAPIWeb.Router.Helpers, as: Routes

      # The default endpoint for testing
      @endpoint NervesHubAPIWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(NervesHubWebCore.Repo)

    unless tags[:async] do
      pid =
        Ecto.Adapters.SQL.Sandbox.start_owner!(NervesHubWebCore.Repo, shared: not tags[:async])

      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    end

    user = Fixtures.user_fixture()
    {:ok, token} = NervesHubWebCore.Accounts.create_user_token(user, "test-token")
    %{cert: cert} = Fixtures.user_certificate_fixture(user)

    user2 = Fixtures.user_fixture(%{username: user.username <> "0"})
    %{cert: cert2} = Fixtures.user_certificate_fixture(user2)

    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org, %{name: "starter"})

    {:ok,
     conn: build_auth_conn(cert),
     conn2: build_auth_conn(cert2),
     org: org,
     user: user,
     user_token: token,
     user2: user2,
     product: product}
  end

  def build_auth_conn(cert) do
    Phoenix.ConnTest.build_conn()
    |> Plug.Test.put_peer_data(peer_data(cert))
    |> Plug.Conn.put_req_header("accept", "application/json")
  end

  def peer_data(cert) do
    %{address: {127, 0, 0, 1}, port: 111_317, ssl_cert: X509.Certificate.to_der(cert)}
  end
end
