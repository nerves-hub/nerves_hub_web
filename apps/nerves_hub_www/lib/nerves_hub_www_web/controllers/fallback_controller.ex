defmodule NervesHubWWWWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use NervesHubWWWWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    [{_, {reason, _}}] = changeset.errors

    conn
    |> put_flash(:error, reason)
    |> redirect(to: referer_path(conn))
  end

  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_flash(:error, reason)
    |> redirect(to: referer_path(conn))
  end

  defp referer_path(conn) do
    referer =
      conn
      |> get_req_header("referer")
      |> List.first()
      |> URI.parse()

    referer.path
  end
end
