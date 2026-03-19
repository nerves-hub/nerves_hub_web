defmodule NervesHubWeb.AshAPIConnCase do
  @moduledoc """
  Test case for Ash JSON:API v2 endpoints.
  """

  use ExUnit.CaseTemplate

  alias NervesHub.Fixtures

  using do
    quote do
      use DefaultMocks

      import NervesHubWeb.AshAPIConnCase, only: [build_json_api_conn: 1]
      import Phoenix.ConnTest
      import Plug.Conn

      @moduletag :tmp_dir
      @endpoint NervesHubWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(NervesHub.Repo)

    if !tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(NervesHub.Repo, {:shared, self()})
    end

    user = Fixtures.user_fixture()
    token = NervesHub.Accounts.create_user_api_token(user, "test-token")

    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org, %{name: "starter"})

    {:ok,
     conn: build_json_api_conn(token),
     org: org,
     user: user,
     product: product}
  end

  def build_json_api_conn(token) do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("authorization", "token #{token}")
    |> Plug.Conn.put_req_header("accept", "application/vnd.api+json")
    |> Plug.Conn.put_req_header("content-type", "application/vnd.api+json")
  end
end
