defmodule NervesHubWeb.Mounts.SetUsersTimezone do
  @moduledoc """
  Add user information to the Sentry context
  """

  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    time_zone =
      if connected?(socket) do
        get_connect_params(socket)["time_zone"] || "UTC"
      else
        "UTC"
      end

    timezone_offset =
      if connected?(socket) do
        get_connect_params(socket)["timezone_offset"] || 0
      else
        0
      end

    {:cont, assign(socket, time_zone: time_zone, timezone_offset: timezone_offset)}
  end
end
