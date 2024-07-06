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
          org: org,
          org_key: org_key,
          user: user,
          product: product,
          device: device,
          deployment: deployment
        } = fixture

        conn =
          build_conn()
          |> init_test_session(%{
            "auth_user_id" => user.id
          })

        %{
          conn: conn,
          user: user,
          org: org,
          fixture: fixture,
          org_key: org_key,
          product: product,
          device: device,
          deployment: deployment
        }
      end
    end
  end
end
