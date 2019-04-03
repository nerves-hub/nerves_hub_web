defmodule NervesHubAPIWeb.OrgUserController do
  use NervesHubAPIWeb, :controller

  alias NervesHubWebCore.Accounts

  action_fallback(NervesHubAPIWeb.FallbackController)

  plug(:validate_role, org: :admin)

  def index(%{assigns: %{org: org}} = conn, _params) do
    org_users = Accounts.get_org_users(org)
    render(conn, "index.json", org_users: org_users)
  end

  def add(%{assigns: %{org: org}} = conn, params) do
    with {:ok, username} <- Map.fetch(params, "username"),
         {:ok, role} <- Map.fetch(params, "role"),
         {:ok, user} <- Accounts.get_user_by_username(username),
         {:ok, org_user} <- Accounts.add_org_user(org, user, %{role: role}) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", org_user_path(conn, :show, org.name, user.username))
      |> render("show.json", org_user: org_user)
    end
  end

  def show(%{assigns: %{org: org}} = conn, %{"username" => username}) do
    with {:ok, user} <- Accounts.get_user_by_username(username),
         {:ok, org_user} <- Accounts.get_org_user(org, user) do
      render(conn, "show.json", org_user: org_user)
    end
  end

  def remove(%{assigns: %{org: org}} = conn, %{"username" => username}) do
    with {:ok, user} <- Accounts.get_user_by_username(username),
         :ok <- Accounts.remove_org_user(org, user) do
      send_resp(conn, :no_content, "")
    end
  end

  def update(%{assigns: %{org: org}} = conn, %{"username" => username} = params) do
    with {:ok, user} <- Accounts.get_user_by_username(username),
         {:ok, org_user} <- Accounts.get_org_user(org, user),
         {:ok, role} <- Map.fetch(params, "role"),
         {:ok, org_user} <- Accounts.change_org_user_role(org_user, role) do
      render(conn, "show.json", org_user: org_user)
    end
  end
end
