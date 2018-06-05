defmodule NervesHubWeb.ConnCase.Browser do
  @moduledoc """
  conn case for browser related tests
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      use NervesHubWeb.ConnCase
      import Plug.Test

      setup do
        {:ok, tenant} = NervesHub.Accounts.create_tenant(%{name: "Browser Tenant"})

        {:ok, default_user} =
          tenant
          |> NervesHub.Accounts.create_user(%{
            name: "Browser User",
            email: "user@browser.com",
            password: "password"
          })

        conn =
          build_conn()
          |> Map.put(:assigns, %{tenant: tenant})
          |> init_test_session(%{"auth_user_id" => default_user.id})

        %{conn: conn, current_user: default_user, current_tenant: tenant}
      end
    end
  end
end
