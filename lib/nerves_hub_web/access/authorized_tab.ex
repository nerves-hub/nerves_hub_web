defmodule NervesHubWeb.Access.AuthorizedTab do
  @moduledoc """
  Makes a device page tab state what authorization each of its events needs.

  A tab handles its events in `hooked_event/3`, attached to the LiveView with
  `attach_hook/4`. When it halts, the LiveView's `handle_event/3` never runs
  and the check in `NervesHubWeb.Access.AuthorizedLiveView` does not see the
  event. So the hook that gets attached is `authorized_hooked_event/3`, defined
  here, which applies the same rules to `hooked_event/3`: every clause needs a
  decorator to compile, the clause that passes an event on included, and a
  refused event halts with the socket as it was and a flash message.
  """

  alias NervesHubWeb.Access.AuthorizedLiveView
  alias NervesHubWeb.Mounts.RequireAuthorization
  alias NervesHubWeb.Mounts.RequireAuthorization.AuthorizationFailed

  defmacro __using__(_) do
    quote do
      use NervesHubWeb.Access.AuthorizationDeclared, hooked_event: 3, handle_progress: 3

      import NervesHubWeb.Access.AuthorizedLiveView, only: [authorized_progress: 1]
      import NervesHubWeb.Mounts.RequireAuthorization, only: [authorize!: 3]

      alias NervesHubWeb.Access.AuthorizedTab

      @dialyzer [:no_match]

      @doc false
      def authorized_hooked_event(event, params, socket), do: AuthorizedTab.run(__MODULE__, event, params, socket)
    end
  end

  @doc false
  def run(module, event, params, socket) do
    callback = "hooked_event/3 for event #{inspect(event)}"

    try do
      event
      |> module.hooked_event(params, RequireAuthorization.wrap(socket))
      |> AuthorizedLiveView.enforce!(module, callback)
    rescue
      e in [AuthorizationFailed, NervesHubWeb.UnauthorizedError] ->
        {:halt, AuthorizedLiveView.deny(socket, e, module, callback)}
    end
  end
end
