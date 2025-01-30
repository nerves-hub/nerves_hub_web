defmodule NervesHubWeb.Mounts.LocalTimezone do
  @moduledoc """
  Fetch the users timezone from the connect params.
  Useful for rendering dates and times correctly.

  This allows us to use the following in our templates:

  ```
  case DateTime.shift_zone(date_time_value, time_zone) do
    {:ok, date_time_in_time_zone} ->
      Calendar.strftime(date_time_in_time_zone, "%B %-d, %Y %-I:%M %p %Z")

    {:error, reason} ->
      {:error, reason}
  end
  ```

  Inspired by https://github.com/zorn/flick/pull/137/files
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [get_connect_params: 1]

  def on_mount(_layout, _params, _session, socket) do
    time_zone = get_connect_params(socket)["time_zone"] || "UTC"

    {:cont, assign(socket, :local_timezone, time_zone)}
  end
end
