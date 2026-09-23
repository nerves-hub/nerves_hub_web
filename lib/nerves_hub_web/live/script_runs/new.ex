defmodule NervesHubWeb.Live.ScriptRuns.New do
  @moduledoc """
  Placeholder for the new-run form.

  The runner itself works — `NervesHub.ScriptRunners.create/3` resolves a filter,
  records a device row apiece and queues the jobs — but the form that would drive
  it (script text, filter type, tags with an operator, pasted identifiers,
  deployment groups) is the next piece of work. This exists so the "Run a Script"
  button has somewhere to go rather than 404ing.
  """

  use NervesHubWeb, :live_view

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    authorized!(:"script_runner:create", socket.assigns.current_scope)

    socket
    |> page_title("Run a Script - #{socket.assigns.current_scope.product.name}")
    |> sidebar_tab(:support_scripts)
    |> ok()
  end
end
