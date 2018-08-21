defmodule NervesHubWWWWeb.ConnCase.Browser do
  @moduledoc """
  conn case for browser related tests
  """
  use ExUnit.CaseTemplate

  alias NervesHubCore.Accounts

  using do
    quote do
      use NervesHubWWWWeb.ConnCase
      import Plug.Test

      setup do
        %{
          org: org,
          org_key: org_key,
          user: user,
          firmware: firmware,
          deployment: deployment,
          product: product
        } = NervesHubCore.Fixtures.standard_fixture()

        {:ok, org_key} =
          Accounts.create_org_key(%{
            org_id: org.id,
            name: "test_key",
            key: File.read!("../../test/fixtures/firmware/fwup-key1.pub")
          })

        {:ok, org_with_org_keys} = org.id |> Accounts.get_org_with_org_keys()

        conn =
          build_conn()
          |> Map.put(:assigns, %{current_org: org_with_org_keys})
          |> init_test_session(%{
            "auth_user_id" => user.id,
            "current_org_id" => org.id
          })

        %{conn: conn, current_user: user, current_org: org, org_key: org_key}
      end
    end
  end
end
