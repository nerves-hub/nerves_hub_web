defmodule NervesHubWeb.Plugs.Org do
  use NervesHubWeb, :plug

  alias NervesHub.Accounts

  def init(opts) do
    opts
  end

  def call(%{params: %{"org_name" => org_name}, assigns: %{user: user}} = conn, _opts) do
    with {:ok, org} <- Accounts.get_org_by_name_and_user(org_name, user),
         {:ok, org} <- Accounts.get_org_with_org_keys(org.id) do
      assign(conn, :org, org)
    else
      _error ->
        conn
        |> put_status(:not_found)
        |> put_view(NervesHubWeb.ErrorView)
        |> render("404.html")
        |> halt
    end
  end
end
