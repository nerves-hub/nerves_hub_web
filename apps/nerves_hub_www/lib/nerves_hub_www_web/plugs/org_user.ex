defmodule NervesHubWWWWeb.Plugs.OrgUser do
  use NervesHubWWWWeb, :plug

  alias NervesHubWebCore.Accounts

  def init(opts) do
    opts
  end

  def call(%{assigns: %{org: org}, params: %{"user_id" => user_id}} = conn, _opts) do
    with {:ok, user} <- Accounts.get_user(user_id),
         {:ok, org_user} <- Accounts.get_org_user(org, user) do
      conn
      |> assign(:org_user, org_user)
    else
      _error ->
        conn
        |> put_status(:not_found)
        |> put_layout(false)
        |> put_view(NervesHubWWWWeb.ErrorView)
        |> render("404.html")
        |> halt
    end
  end
end
