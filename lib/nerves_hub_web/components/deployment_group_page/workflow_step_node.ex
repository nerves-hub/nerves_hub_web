defmodule NervesHubWeb.Components.DeploymentGroupPage.WorkflowStepNode do
  @moduledoc """
  One step drawn on the workflow diagram.

  A LiveComponent rather than a function component because of the skip control:
  LiveFlow hands a function component the node and nothing else, so it has no
  `@myself` to send an event to. A module in `node_types` is rendered as a live
  component and gets one.

  Skipping is here because it applies to any step, wherever the workflow has got
  to. Retrying only applies to the step that failed, and that step already has a
  bar above the diagram naming it, so it lives there instead.
  """

  use NervesHubWeb, :live_component

  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ManagedDeployments.Workflows

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
    |> assign(:width, node.data[:content_width])
    |> ok()
  end

  @impl Phoenix.LiveComponent
  def handle_event("skip", _params, socket) do
    send(self(), {:workflow_step_action, :skip, socket.assigns.number})

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

      <button
        :if={@skippable?}
        type="button"
        phx-click="skip"
        phx-target={@myself}
        aria-label={"Skip step: #{@label}"}
        title="Skip this step"
        data-confirm={"Skip \"#{@label}\"? Its devices will be picked up by a later step."}
        class="bg-base-800 border-base-600 hover:bg-base-700 hover:text-base-50 text-base-200 absolute -top-1 -right-1 rounded border px-2 py-0.5 text-[10px] font-medium opacity-0 transition-opacity group-hover/step:opacity-100 hover:cursor-pointer focus-visible:opacity-100"
      >
        Skip
      </button>
    </div>
    """
  end

  @doc """
  What LiveFlow should draw each kind of step with.
  """
  def node_types(), do: %{status: __MODULE__}

  @doc """
  The parts of a step the diagram needs to draw it and act on it.
  """
  @spec node_data(DeploymentWorkflowStep.t(), pos_integer()) :: map()
  def node_data(step, content_width) do
    %{
      content_width: content_width,
      detail: step.description,
      label: DeploymentWorkflowStep.label(step),
      number: step.number,
      skippable?: Workflows.skippable?(step),
      status: step.status
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
