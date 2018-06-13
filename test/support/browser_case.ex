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

        NervesHub.Accounts.create_tenant_key(%{
          tenant_id: tenant.id,
          name: "test_key",
          key: File.read!("test/fixtures/firmware/fwup-key1.pub")
        })

        {:ok, tenant_with_key} = NervesHub.Accounts.get_tenant(tenant.id)

        {:ok, default_user} =
          tenant_with_key
          |> NervesHub.Accounts.create_user(%{
            name: "Browser User",
            email: "user@browser.com",
            password: "password"
          })

        conn =
          build_conn()
          |> Map.put(:assigns, %{tenant: tenant_with_key})
          |> init_test_session(%{"auth_user_id" => default_user.id})

        %{conn: conn, current_user: default_user, current_tenant: tenant}
      end
    end
  end
end
