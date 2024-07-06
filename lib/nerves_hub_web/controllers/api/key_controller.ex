defmodule NervesHubWeb.API.KeyController do
  use NervesHubWeb, :api_controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.{OrgKey}

  action_fallback(NervesHubWeb.API.FallbackController)

  plug(:validate_role, [org: :manage] when action in [:create, :delete])
  plug(:validate_role, [org: :view] when action in [:index, :show])

  def index(%{assigns: %{org: org}} = conn, _params) do
    keys = Accounts.list_org_keys(org)
    render(conn, "index.json", keys: keys)
  end

  def create(%{assigns: %{user: user, org: org}} = conn, params) do
    params =
      Map.take(params, ["name", "key"])
      |> Map.put("org_id", org.id)
      |> Map.put("created_by_id", user.id)

    with {:ok, key} <- Accounts.create_org_key(params) do
      conn
      |> put_status(:created)
      |> render("show.json", key: key)
    end
  end

  def show(%{assigns: %{org: org}} = conn, %{"name" => name}) do
    with {:ok, key} <- Accounts.get_org_key_by_name(org, name) do
      render(conn, "show.json", key: key)
    end
  end

  def delete(%{assigns: %{org: org}} = conn, %{"name" => name}) do
    with {:ok, key} <- Accounts.get_org_key_by_name(org, name),
         {:ok, %OrgKey{}} <- Accounts.delete_org_key(key) do
      send_resp(conn, :no_content, "")
    end
  end
end
