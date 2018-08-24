defmodule NervesHubWWWWeb.SessionController do
  use NervesHubWWWWeb, :controller

  alias NervesHubCore.Accounts
  alias NervesHubCore.Accounts.User

  @session_key "auth_user_id"

  def new(conn, _params) do
    conn
    |> get_session(@session_key)
    |> case do
      nil ->
        render(conn, "new.html")

      _ ->
        conn
        |> redirect(to: dashboard_path(conn, :index))
    end
  end

  def create(conn, %{"login" => %{"email" => email, "password" => password}}) do
    email
    |> Accounts.authenticate(password)
    |> case do
      {:ok, %User{id: user_id, orgs: [def_org | _]}} ->
        conn
        |> put_session(@session_key, user_id)
        |> put_session("current_org_id", def_org.id)
        |> redirect(to: dashboard_path(conn, :index))

      {:error, :authentication_failed} ->
        conn
        |> put_flash(:error, "Login Failed")
        |> redirect(to: session_path(conn, :new))
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session(@session_key)
    |> redirect(to: "/")
  end

  def set_org(%{assigns: %{current_org: _, user: user}} = conn, %{"org" => id}) do
    {org_id, _} = Integer.parse(id)

    if org_id in (user.orgs |> Enum.map(fn x -> x.id end)) do
      conn
      |> put_session("current_org_id", org_id)
      |> redirect(to: dashboard_path(conn, :index))
    else
      conn
      |> redirect(to: dashboard_path(conn, :index))
    end
  end
end
