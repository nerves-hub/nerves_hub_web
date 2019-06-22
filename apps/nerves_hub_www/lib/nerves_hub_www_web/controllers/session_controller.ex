defmodule NervesHubWWWWeb.SessionController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.Accounts.User

  @session_key "auth_user_id"

  def new(conn, _params) do
    conn
    |> get_session(@session_key)
    |> case do
      nil ->
        render(conn, "new.html")

      _ ->
        conn
        |> redirect(to: product_path(conn, :index))
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
        |> redirect(to: product_path(conn, :index))

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

  def set_org(conn, %{"org" => id} = params) do
    {org_id, _} = Integer.parse(id)
    redirect = Map.get(params, "redirect", product_path(conn, :index))

    conn
    |> put_current_org(org_id)
    |> redirect(to: redirect)
  end

  defp put_current_org(%{assigns: %{current_org: _, user: user}} = conn, org_id) do
    user_orgs =
      Accounts.get_user_orgs_with_product_role(user, :read)
      |> Enum.map(fn x -> x.id end)

    if org_id in user_orgs do
      put_session(conn, "current_org_id", org_id)
    else
      conn
    end
  end
end
