defmodule NervesHubWeb.ConnCase.Browser do
  @moduledoc """
  conn case for browser related tests
  """
  alias NervesHub.Fixtures
  alias NervesHubWeb.ConnCase
  alias Plug.Test

  defmacro __using__(opts) do
    quote do
      use DefaultMocks
      use ConnCase, unquote(opts)
      use NervesHubWeb, :verified_routes

      import Test
      import Phoenix.LiveViewTest
      import PhoenixTest

      @moduletag :tmp_dir

      setup context do
        fixture = Fixtures.standard_fixture(context.tmp_dir)

        %{
          deployment_group: deployment_group,
          device: device,
          org: org,
          org_key: org_key,
          product: product,
          user: user
        } = fixture

        token = NervesHub.Accounts.create_user_session_token(user)

        conn =
          build_conn()
          |> init_test_session(%{
            "user_token" => token
          })

        %{
          conn: conn,
          deployment_group: deployment_group,
          device: device,
          fixture: fixture,
          org: org,
          org_key: org_key,
          product: product,
          user: user
        }
      end
    end
  end
end
