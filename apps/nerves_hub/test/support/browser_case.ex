defmodule NervesHubWeb.ConnCase.Browser do
  @moduledoc """
  conn case for browser related tests
  """
  use ExUnit.CaseTemplate

  alias NervesHubCore.Accounts

  using do
    quote do
      use NervesHubWeb.ConnCase
      import Plug.Test

      setup do
        %{
          tenant: tenant,
          tenant_key: tenant_key,
          user: user,
          firmware: firmware,
          deployment: deployment,
          product: product
        } = NervesHub.Fixtures.very_fixture()

        {:ok, tenant_key} =
          Accounts.create_tenant_key(%{
            tenant_id: tenant.id,
            name: "test_key",
            key: File.read!("../../test/fixtures/firmware/fwup-key1.pub")
          })

        conn =
          build_conn()
          |> Map.put(:assigns, %{tenant: tenant})
          |> init_test_session(%{"auth_user_id" => user.id})

        %{conn: conn, current_user: user, current_tenant: tenant, tenant_key: tenant_key}
      end
    end
  end
end
