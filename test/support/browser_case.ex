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
      use Oban.Testing, repo: NervesHub.ObanRepo

      import Test
      import Phoenix.LiveViewTest
      import PhoenixTest

      @moduletag :tmp_dir

      setup context do
        fixture = Fixtures.standard_fixture(context.tmp_dir)

        %{
          org: org,
          org_key: org_key,
          user: user,
          product: product,
          device: device,
          deployment_group: deployment_group
        } = fixture

        token = NervesHub.Accounts.create_user_session_token(user)

        conn =
          build_conn()
          |> init_test_session(%{
            "user_token" => token
          })

        %{
          conn: conn,
          user: user,
          org: org,
          fixture: fixture,
          org_key: org_key,
          product: product,
          device: device,
          deployment_group: deployment_group
        }
      end
    end
  end
end
