defmodule NervesHubWeb.Mounts.SetUsersTimezone do
  @moduledoc """
  Assigns the viewer's IANA time zone, used to render every timestamp in the UI.

  A connected mount takes the zone straight from the socket connect params. The
  initial static render has no connect params, so it falls back to the cookie
  `NervesHubWeb.Plugs.Timezone` put in the session — otherwise the first paint
  would be UTC and would visibly change once the LiveView connected.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias NervesHubWeb.Helpers.Timezone

  def on_mount(:default, _params, session, socket) do
    connect_params = if connected?(socket), do: get_connect_params(socket) || %{}, else: %{}

    time_zone = Timezone.resolve([connect_params["time_zone"], session["time_zone"]])
    timezone_offset = connect_params["timezone_offset"] || 0

    {:cont, assign(socket, time_zone: time_zone, timezone_offset: timezone_offset)}
  end
end
