defmodule NervesHubWeb.API.OrgUserController do
  use NervesHubWeb, :api_controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserNotifier

  plug(:validate_role, org: :admin)

  def index(%{assigns: %{org: org}} = conn, _params) do
    org_users = Accounts.get_org_users(org)
    render(conn, :index, org_users: org_users)
  end

  def add(%{assigns: %{org: org}} = conn, params) do
    with {:ok, user_id} <- Map.fetch(params, "user_id"),
         {:ok, role} <- Map.fetch(params, "role"),
         {:ok, user} <- Accounts.get_user(user_id),
         {:ok, org_user} <- Accounts.add_org_user(org, user, %{role: role}) do
      # Now let every admin in the organization - except the new person -
      # know about this new user.
      instigator = conn.assigns.user

      UserNotifier.deliver_all_tell_org_user_added(org, instigator, user)

      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        Routes.api_org_user_path(conn, :show, org.name, user.id)
      )
      |> render(:show, org_user: org_user)
    end
  end

  def show(%{assigns: %{org: org}} = conn, %{"user_id" => user_id}) do
    with {:ok, user} <- Accounts.get_user(user_id),
         {:ok, org_user} <- Accounts.get_org_user(org, user) do
      render(conn, :show, org_user: org_user)
    end
  end

  def remove(%{assigns: %{org: org, user: user}} = conn, %{"user_id" => user_id}) do
    with {:ok, user_to_remove} <- Accounts.get_user(user_id),
         {:ok, _org_user} <- Accounts.get_org_user(org, user_to_remove),
         :ok <- Accounts.remove_org_user(org, user_to_remove) do
      # Now let every admin in the organization know
      # that this user has been removed from the organization.
      UserNotifier.deliver_all_tell_org_user_removed(org, user, user_to_remove)

      send_resp(conn, :no_content, "")
    end
  end

  def update(%{assigns: %{org: org}} = conn, %{"user_id" => user_id} = params) do
    with {:ok, user} <- Accounts.get_user(user_id),
         {:ok, org_user} <- Accounts.get_org_user(org, user),
         {:ok, role} <- Map.fetch(params, "role"),
         {:ok, org_user} <- Accounts.change_org_user_role(org_user, role) do
      render(conn, :show, org_user: org_user)
    end
  end
end
