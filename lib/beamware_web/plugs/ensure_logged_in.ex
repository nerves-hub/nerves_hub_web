defmodule BeamwareWeb.Plugs.EnsureLoggedIn do
  import Plug.Conn

  alias Phoenix.Controller
  alias Plug.Conn
  alias Beamware.Accounts

  @session_key "auth_user_id"

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    conn
    |> Conn.get_session(@session_key)
    |> case do
      nil -> nil
      user_id -> Accounts.get_user(user_id)
    end
    |> case do
      {:ok, user} ->
        # Paranoidly remove password hash so it isn't in `conn.assigns.current_user`, in case some error message is leaked
        conn
        |> assign(:user, %{user | password_hash: nil})

      _ ->
        conn
        |> Controller.put_flash(:error, "You must login to access this page.")
        |> Controller.redirect(to: "/")
        |> halt()
    end
  end
end
