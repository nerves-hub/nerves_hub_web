defmodule NervesHubWeb.API.KeyController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Accounts.User

  security([%{}, %{"bearer_auth" => []}])
  tags(["Signing Keys"])

  plug(:validate_role, [org: :manage] when action in [:create, :delete])
  plug(:validate_role, [org: :view] when action in [:index, :show])

  operation(:index, summary: "List all Firmware and Archive Signing Keys for an Organization")

  def index(%{assigns: %{org: org}} = conn, _params) do
    keys = Accounts.list_org_keys(org)
    render(conn, :index, keys: keys)
  end

  operation(:create, summary: "Create a new Signing Key for an Organization")

  def create(%{assigns: %{actor: actor, org: org}} = conn, params) do
    created_by_id =
      case actor do
        %User{id: id} -> id
        _ -> nil
      end

    params =
      Map.take(params, ["name", "key"])
      |> Map.put("org_id", org.id)
      |> Map.put("created_by_id", created_by_id)

    with {:ok, key} <- Accounts.create_org_key(params) do
      conn
      |> put_status(:created)
      |> render(:show, key: key)
    end
  end

  operation(:show, summary: "Show a Signing Key for an Organization")

  def show(%{assigns: %{org: org}} = conn, %{"name" => name}) do
    with {:ok, key} <- Accounts.get_org_key_by_name(org, name) do
      render(conn, :show, key: key)
    end
  end

  operation(:delete, summary: "Delete a Signing Key for an Organization")

  def delete(%{assigns: %{org: org}} = conn, %{"name" => name}) do
    with {:ok, key} <- Accounts.get_org_key_by_name(org, name),
         {:ok, %OrgKey{}} <- Accounts.delete_org_key(key) do
      send_resp(conn, :no_content, "")
    end
  end
end
