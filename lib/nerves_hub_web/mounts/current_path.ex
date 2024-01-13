defmodule NervesHubWeb.Mounts.CurrentPath do
  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _assigns, _session, socket) do
    socket =
      attach_hook(socket, :current_uri, :handle_params, fn
        _params, uri, socket ->
          %URI{
            path: path
          } = URI.parse(uri)

          {:cont, assign(socket, current_path: path)}
      end)

    {:cont, socket}
  end
end
