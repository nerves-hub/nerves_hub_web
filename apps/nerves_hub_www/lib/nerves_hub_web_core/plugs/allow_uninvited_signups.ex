defmodule NervesHubWebCore.Plugs.AllowUninvitedSignups do
  import Plug.Conn

  alias NervesHubAPIWeb.Router, as: APIRouter
  alias NervesHubWWWWeb.Router, as: WebRouter

  alias Phoenix.Controller

  def init(opts), do: opts

  def call(%{private: %{phoenix_router: APIRouter}} = conn, _opts) do
    if allow_signups?() do
      conn
    else
      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(
        403,
        Jason.encode!(%{status: "Public signups disabled. Invite required to signup"})
      )
      |> halt()
    end
  end

  def call(%{private: %{phoenix_router: WebRouter}} = conn, _opts) do
    if allow_signups?() do
      conn
    else
      conn
      |> Controller.put_flash(:error, "Sorry signups are not enabled at this time.")
      |> Controller.redirect(to: "/")
      |> halt()
    end
  end

  defp allow_signups?() do
    Application.get_env(:nerves_hub_www, :allow_signups?)
  end
end
