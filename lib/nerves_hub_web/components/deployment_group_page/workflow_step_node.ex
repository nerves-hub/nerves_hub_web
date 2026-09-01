defmodule NervesHubWeb.Components.DeploymentGroupPage.WorkflowStepNode do
  @moduledoc """
  One step drawn on the workflow diagram.

  A LiveComponent rather than a function component because the controls on it
  need somewhere to send their events. LiveFlow renders a `node_types` entry that
  is a module as a live component, which gives this its own `@myself`; a function
  component is handed nothing but the node and so has no way to be interactive.

  The step itself is acted on by the LiveView, which owns the deployment group and
  the diagram, so the controls here only say what was asked for.
  """

  use NervesHubWeb, :live_component

  @colours %{
    waiting: {"#f59e0b", "Waiting"},
    in_progress: {"#615fff", "In Progress"},
    completed: {"#22c55e", "Completed"},
    skipped: {"#a1a1aa", "Skipped"},
    error: {"#ef4444", "Failed"}
  }

  @impl Phoenix.LiveComponent
  def update(%{node: node} = assigns, socket) do
    {colour, status_label} = Map.get(@colours, node.data[:status], {"#a1a1aa", "Unknown"})

    socket
    |> assign(assigns)
    |> assign(:label, node.data[:label] || "Step")
    |> assign(:detail, node.data[:detail])
    |> assign(:status, node.data[:status])
    |> assign(:status_colour, colour)
    |> assign(:status_label, status_label)
    |> assign(:number, node.data[:number])
    |> assign(:skippable?, node.data[:skippable?] == true)
    |> assign(:retryable?, node.data[:retryable?] == true)
    |> assign(:width, node.data[:content_width])
    |> ok()
  end

  @impl Phoenix.LiveComponent
  def handle_event("skip", _params, socket) do
    send(self(), {:workflow_step_action, :skip, socket.assigns.number})

    {:noreply, socket}
  end

  def handle_event("retry", _params, socket) do
    send(self(), {:workflow_step_action, :retry, socket.assigns.number})

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="group/step relative" style={"width: #{@width}px"}>
      <div style="display: flex; align-items: center; gap: 8px">
        <div style={"width: 10px; height: 10px; border-radius: 50%; background: #{@status_colour}; box-shadow: 0 0 6px #{@status_colour}80;#{@status == :in_progress && " animation: pulse 2s infinite;"}"}>
        </div>
        <div>
          <div style="font-weight: 600; font-size: 13px; color: var(--lf-text-primary)">
            {@label}
          </div>
          <div style={"font-size: 11px; font-weight: 500; color: #{@status_colour}"}>
            {@status_label}
          </div>
        </div>
      </div>

      <div
        :if={@detail}
        style="font-size: 11px; color: var(--lf-text-muted); margin-top: 6px; padding-top: 6px; border-top: 1px solid var(--lf-border-secondary, #ddd); display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden"
        title={@detail}
      >
        {@detail}
      </div>

      <div
        :if={@skippable? or @retryable?}
        class="absolute -top-1 -right-1 flex gap-1 opacity-0 transition-opacity group-hover/step:opacity-100 focus-within:opacity-100"
      >
        <button
          :if={@retryable?}
          type="button"
          phx-click="retry"
          phx-target={@myself}
          aria-label={"Retry step: #{@label}"}
          title="Retry this step"
          class="bg-base-800 border-base-600 hover:bg-base-700 hover:text-base-50 text-base-200 rounded border px-2 py-0.5 text-[10px] font-medium hover:cursor-pointer"
        >
          Retry
        </button>

        <button
          :if={@skippable?}
          type="button"
          phx-click="skip"
          phx-target={@myself}
          aria-label={"Skip step: #{@label}"}
          title="Skip this step"
          data-confirm={"Skip \"#{@label}\"? Its devices will be picked up by a later step."}
          class="bg-base-800 border-base-600 hover:bg-base-700 hover:text-base-50 text-base-200 rounded border px-2 py-0.5 text-[10px] font-medium hover:cursor-pointer"
        >
          Skip
        </button>
      </div>
    </div>
    """
  end
end
