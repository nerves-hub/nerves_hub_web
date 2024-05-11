defmodule NervesHubWeb.Plugs.AdminBasicAuth do
  use NervesHubWeb, :plug

  def init(_opts), do: []

  def call(conn, _opts) do
    admin_auth = Application.get_env(:nerves_hub, :admin_auth, [])

    username = admin_auth[:username]
    password = admin_auth[:password]

    dev_env = Application.get_env(:nerves_hub, :deploy_env) == "dev"

    cond do
      dev_env ->
        conn

      username && password ->
        Plug.BasicAuth.basic_auth(conn, username: username, password: password)

      true ->
        conn
        |> resp(401, "Unauthorized")
        |> halt()
    end
  end
end
