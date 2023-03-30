defmodule NervesHubWeb.Plugs.Org do
  use NervesHubWeb, :plug

  alias NervesHub.Repo

  def init(opts) do
    opts
  end

  def call(%{params: %{"org_name" => org_name}} = conn, _opts) do
    %{orgs: orgs} = conn.assigns

    org =
      Enum.find(orgs, fn org ->
        org.name == org_name
      end)

    case !is_nil(org) do
      true ->
        assign(conn, :org, Repo.preload(org, [:org_keys]))

      false ->
        conn
        |> put_status(:not_found)
        |> put_view(NervesHubWeb.ErrorView)
        |> render("404.html")
        |> halt()
    end
  end
end
