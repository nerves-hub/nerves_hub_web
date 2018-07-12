defmodule NervesHubWeb.Plugs.AllowUninvitedSignups do
  import Plug.Conn

  alias Phoenix.Controller

  def init(opts) do
    opts
    |> Keyword.put(:allow_uninvited, allow_uninvited_users())
  end

  def call(conn, allow_uninvited: true), do: conn

  def call(conn, _opts) do
    conn
    |> Controller.put_flash(:error, "Sorry signups are not enabled at this time.")
    |> Controller.redirect(to: "/")
    |> halt()
  end

  defp allow_uninvited_users do
    Application.get_env(:nerves_hub, NervesHubWeb.AccountController)[:allow_signups]
  end
end
