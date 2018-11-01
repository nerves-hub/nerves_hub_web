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

  @certificate Path.join([__DIR__, "../../../../test/fixtures/ssl/user.pem"])

  use ExUnit.CaseTemplate
  alias NervesHubCore.Fixtures

  using do
    quote do
      # Import conveniences for testing with connections
      use Phoenix.ConnTest
      import NervesHubAPIWeb.Router.Helpers
      import NervesHubAPIWeb.ConnCase, only: [build_auth_conn: 0, peer_data: 0]

      # The default endpoint for testing
      @endpoint NervesHubAPIWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(NervesHubCore.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(NervesHubCore.Repo, {:shared, self()})
    end

    org = Fixtures.org_fixture()
    user = Fixtures.user_fixture(%{orgs: [org]})
    product = Fixtures.product_fixture(org, %{name: "starter"})

    {:ok, conn: build_auth_conn(), org: org, user: user, product: product}
  end

  def build_auth_conn() do
    Phoenix.ConnTest.build_conn()
    |> Plug.Test.put_peer_data(peer_data())
    |> Plug.Conn.put_req_header("accept", "application/json")
  end

  def peer_data() do
    certificate = File.read!(@certificate)
    [{:Certificate, certificate, _}] = :public_key.pem_decode(certificate)
    %{address: {127, 0, 0, 1}, port: 111_317, ssl_cert: certificate}
  end
end
