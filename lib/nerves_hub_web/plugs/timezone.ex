defmodule NervesHubWeb.Plugs.Timezone do
  @moduledoc """
  Copies the browser's `time_zone` cookie into the session.

  LiveView only learns the viewer's zone from the socket connect params, which
  aren't available for the initial static render. Without this the first paint of
  every page would be in UTC and then visibly flip to local time a moment later,
  once the LiveView connects. `assets/js/app.js` writes the cookie, this plug
  hands it to the session, and `NervesHubWeb.Mounts.SetUsersTimezone` reads it.
  """

  import Plug.Conn

  alias NervesHubWeb.Helpers.Timezone

  @cookie "time_zone"

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    case Timezone.validate(conn.cookies[@cookie]) do
      {:ok, time_zone} -> put_session(conn, @cookie, time_zone)
      :error -> conn
    end
  end
end
