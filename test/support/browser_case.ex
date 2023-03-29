defmodule NervesHubWeb.ConnCase.Browser do
  @moduledoc """
  conn case for browser related tests
  """
  alias NervesHub.{Accounts, Fixtures}
  alias NervesHubWeb.ConnCase
  alias Plug.Test

  defmacro __using__(opts) do
    quote do
      use DefaultMocks
      use ConnCase, unquote(opts)
      import Test
      import Phoenix.LiveViewTest

      setup do
        fixture = Fixtures.standard_fixture()

        %{org: org, org_key: org_key, user: user} = fixture

        {:ok, org_with_org_keys} = Accounts.get_org_with_org_keys(org.id)

        conn =
          build_conn()
          |> Map.put(:assigns, %{org: org_with_org_keys, user: user, orgs: [org]})
          |> init_test_session(%{
            "auth_user_id" => user.id
          })

        %{conn: conn, user: user, org: org, fixture: fixture, org_key: org_key}
      end
    end
  end
end
