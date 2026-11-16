defmodule NervesHubWeb.Access.AuthorizedLiveComponent do
  @moduledoc """
  Makes a LiveComponent state what authorization each of its events needs.

  An event sent to a component (`phx-target={@myself}`) never reaches the
  LiveView's `handle_event/3`, so the check in
  `NervesHubWeb.Access.AuthorizedLiveView` does not see it. This applies the
  same rules to the component's own `handle_event/3`: every clause needs a
  decorator to compile, and a refused event leaves the component as it was and
  shows the user the same message.

  A refusal is shown by the LiveView, which the component asks with a message
  (see `NervesHubWeb.Mounts.RequireAuthorization.on_mount/4`), as a flash on a
  component's own socket is never rendered.

  The decorators read `socket.assigns.current_scope`, so a component that
  checks a permission has to be given the scope by whoever renders it.
  """

  defmacro __using__(_) do
    quote do
      use NervesHubWeb.Access.AuthorizationDeclared, handle_event: 3, handle_progress: 3

      import NervesHubWeb.Access.AuthorizedLiveView, only: [authorized_progress: 1, is_wrapped: 1]
      import NervesHubWeb.Mounts.RequireAuthorization, only: [authorize!: 3]

      alias NervesHubWeb.Access.AuthorizedLiveView
      alias NervesHubWeb.Mounts.RequireAuthorization
      alias NervesHubWeb.Mounts.RequireAuthorization.AuthorizationFailed

      @dialyzer [:no_match]

      @impl Phoenix.LiveComponent
      def handle_event(event, params, %{private: private} = socket) when not is_wrapped(private) do
        event
        |> handle_event(params, RequireAuthorization.wrap(socket))
        |> AuthorizedLiveView.enforce!(__MODULE__, "handle_event/3 for event #{inspect(event)}")
      rescue
        e in [AuthorizationFailed, NervesHubWeb.UnauthorizedError] ->
          {:noreply,
           AuthorizedLiveView.deny_in_component(socket, e, __MODULE__, "handle_event/3 for event #{inspect(event)}")}
      end
    end
  end
end
