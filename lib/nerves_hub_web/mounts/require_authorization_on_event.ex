defmodule NervesHubWeb.Mounts.RequireAuthzOnEvent do
  import Phoenix.LiveView

  defmodule AuthorizationNotApplied do
    defexception [:message]
  end

  defmodule AuthorizationFailed do
    defexception [:message]
  end

  def on_mount(_, _assigns, _session, socket) do
    # always flips authorization back to false, enforcing the developer
    # manages it
    socket =
      socket
      |> put_private(:wrapped_in_authorization?, false)
      |> put_private(:authorization_applied?, false)
      |> put_private(:authorization_granted?, false)
      |> attach_hook(:require_authorization, :handle_event, &event/3)
      |> attach_hook(:require_authorization, :handle_params, &params/3)

    {:cont, socket}
  end

  defp event(_, _, socket) do
    socket =
      socket
      |> put_private(:wrapped_in_authorization?, false)
      |> put_private(:authorization_applied?, false)
      |> put_private(:authorization_granted?, false)

    {:cont, socket}
  end

  defp params(_, _, socket) do
    socket =
      socket
      |> put_private(:wrapped_in_authorization?, false)
      |> put_private(:authorization_applied?, false)
      |> put_private(:authorization_granted?, false)

      {:cont, socket}
  end

  def wrap(socket), do: put_private(socket, :wrapped_in_authorization?, true)
end
