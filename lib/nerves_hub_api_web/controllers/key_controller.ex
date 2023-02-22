defmodule NervesHubAPIWeb.KeyController do
  use NervesHubAPIWeb, :controller

  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.Accounts.{OrgKey}

  action_fallback(NervesHubAPIWeb.FallbackController)

  plug(:validate_role, [org: :delete] when action in [:delete])
  plug(:validate_role, [org: :write] when action in [:create])
  plug(:validate_role, [org: :read] when action in [:index, :show])

  def index(%{assigns: %{org: org}} = conn, _params) do
    keys = Accounts.list_org_keys(org)
    render(conn, "index.json", keys: keys)
  end

  def create(%{assigns: %{org: org}} = conn, params) do
    params =
      Map.take(params, ["name", "key"])
      |> Map.put("org_id", org.id)

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
