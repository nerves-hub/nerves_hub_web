defmodule NervesHubWeb.Components.DeploymentGroupPage.WorkflowStepNode do
  @moduledoc """
  One step drawn on the workflow diagram.

  Acting on a step is done from the bar above the diagram rather than from the
  node, so this only has to draw. LiveFlow hands a function component the node
  and nothing else, which is all this needs.
  """

  use NervesHubWeb, :html

  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep

  @colours %{
    waiting: {"#f59e0b", "Waiting"},
    in_progress: {"#615fff", "In Progress"},
    completed: {"#22c55e", "Completed"},
    skipped: {"#a1a1aa", "Skipped"},
    error: {"#ef4444", "Failed"}
  }

  attr(:node, :map, required: true)

  def render(assigns) do
    node = assigns.node
    {colour, status_label} = Map.get(@colours, node.data[:status], {"#a1a1aa", "Unknown"})

    assigns =
      assigns
      |> assign(:label, node.data[:label] || "Step")
      |> assign(:detail, node.data[:detail])
      |> assign(:status, node.data[:status])
      |> assign(:status_colour, colour)
      |> assign(:status_label, status_label)
      |> assign(:width, node.data[:content_width])

    ~H"""
    <div style={"width: #{@width}px"}>
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
    </div>
    """
  end

  @doc """
  What LiveFlow should draw each kind of step with.
  """
  def node_types(), do: %{status: &__MODULE__.render/1}

  @doc """
  The parts of a step the diagram needs to draw it.
  """
  @spec node_data(DeploymentWorkflowStep.t(), pos_integer()) :: map()
  def node_data(step, content_width) do
    %{
      content_width: content_width,
      detail: step.description,
      label: DeploymentWorkflowStep.label(step),
      status: step.status
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
