defmodule NervesHubWWWWeb.Plugs.FetchOrg do
  import Plug.Conn

  alias NervesHubWebCore.Accounts

  def init(opts) do
    opts
  end

  def call(%{params: %{"org_id" => org_id}} = conn, _opts) do
    org = Accounts.get_org(org_id)

    conn
    |> assign(:org, org)
  end

  def call(%{assigns: %{user: user}} = conn, _opts) do
    user.org_id
    |> Accounts.get_org()
    |> case do
      {:ok, org} ->
        conn
        |> assign(:org, org)

      _ ->
        conn
        |> halt()
    end
  end
end
