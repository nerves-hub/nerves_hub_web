defmodule NervesHubWWWWeb.Plugs.Org do
  use NervesHubWWWWeb, :plug

  alias NervesHubWebCore.Accounts

  def init(opts) do
    opts
  end

  def call(%{params: %{"org_name" => org_name}, assigns: %{user: user}} = conn, _opts) do
    with {:ok, org} <- Accounts.get_org_by_name_and_user(org_name, user),
         {:ok, org} <- Accounts.get_org_with_org_keys(org.id),
         limit <- Accounts.get_org_limit_by_org_id(org.id) do
      conn
      |> assign(:org, org)
      |> assign(:current_limit, limit)
    else
      _error ->
        conn
        |> put_status(:not_found)
        |> put_view(NervesHubWWWWeb.ErrorView)
        |> render("404.html")
        |> halt
    end
  end
end
