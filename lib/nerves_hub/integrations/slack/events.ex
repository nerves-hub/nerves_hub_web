defmodule NervesHub.Integrations.Slack.Events do
  @moduledoc """
  The events a Slack channel can be sent.

  Fewer than a webhook can subscribe to: a channel is read by people, so it
  gets the events a person acts on, not telemetry. Each is built from an
  event `NervesHub.Integrations.dispatch/3` raises (its `source`), and a
  source can feed more than one: a finished update is posted as a failure or
  a success, so a channel can have one without the other.
  """

  @typedoc "One event a channel can be sent, as the settings page describes it."
  @type event() :: %{key: String.t(), source: String.t(), label: String.t(), description: String.t()}

  @events [
    %{
      key: "device.health_status_changed",
      source: "device.health_status_changed",
      label: "Health status changed",
      description: "A device's health status moved, such as from healthy to warning."
    },
    %{
      key: "device.firmware_update.failed",
      source: "device.firmware_update.finished",
      label: "Update failed",
      description:
        "A device's update failed, stopped reporting progress, or ended with the device back on its old firmware."
    },
    %{
      key: "device.firmware_update.succeeded",
      source: "device.firmware_update.finished",
      label: "Update succeeded",
      description: "A device finished updating."
    },
    %{
      key: "error_group.created",
      source: "error_group.created",
      label: "New error",
      description: "A device reported an error not seen before in its product."
    },
    %{
      key: "error_group.reopened",
      source: "error_group.reopened",
      label: "Error reopened",
      description: "An error that was marked resolved happened again."
    },
    %{
      key: "deployment_group.workflow_step.started",
      source: "deployment_group.workflow_step.started",
      label: "Workflow step started",
      description: "A deployment group's workflow began a step, or began it again after somebody retried it."
    },
    %{
      key: "deployment_group.workflow_step.awaiting_approval",
      source: "deployment_group.workflow_step.awaiting_approval",
      label: "Workflow waiting for approval",
      description:
        "A workflow reached a step that holds the rollout until somebody approves it, with an Approve button."
    },
    %{
      key: "deployment_group.workflow_step.completed",
      source: "deployment_group.workflow_step.completed",
      label: "Workflow step completed",
      description: "Every device a step covers is on the release's firmware, or somebody approved an approval step."
    },
    %{
      key: "deployment_group.workflow_step.failed",
      source: "deployment_group.workflow_step.failed",
      label: "Workflow step failed",
      description: "Too many of a step's devices failed to update and the rollout stopped, with Retry and Skip buttons."
    },
    %{
      key: "deployment_group.workflow_step.skipped",
      source: "deployment_group.workflow_step.skipped",
      label: "Workflow step skipped",
      description: "Somebody skipped a step, and its devices were left to the steps after it."
    },
    %{
      key: "product.notification_created",
      source: "product.notification_created",
      label: "Product notifications",
      description:
        "Something NervesHub flags on a product's Notifications page, such as a halted deployment workflow or a webhook it turned off."
    }
  ]

  @keys Enum.map(@events, & &1.key)

  @failed_outcomes ["failed", "expired", "abandoned"]

  @doc "Every event a channel can be sent, in the order the settings page lists them."
  @spec all() :: [event(), ...]
  def all(), do: @events

  @doc "Every event key."
  @spec keys() :: [String.t(), ...]
  def keys(), do: @keys

  @doc "The human name of an event key, falling back to the key itself."
  @spec label(String.t()) :: String.t()
  def label(key) do
    case Enum.find(@events, &(&1.key == key)) do
      %{label: label} -> label
      nil -> key
    end
  end

  @doc "The event types `NervesHub.Integrations` must hand over for these keys."
  @spec sources([String.t()]) :: [String.t()]
  def sources(keys) do
    for %{key: key, source: source} <- @events, key in keys, uniq: true, do: source
  end

  @doc """
  Which event key a raised event is, or `nil` when it is not one a channel
  is sent: an update that was ignored or rescheduled, for instance.
  """
  @spec key(String.t(), map()) :: String.t() | nil
  def key("device.firmware_update.finished", data) do
    case Map.get(data, :outcome) do
      "succeeded" -> "device.firmware_update.succeeded"
      outcome when outcome in @failed_outcomes -> "device.firmware_update.failed"
      _other -> nil
    end
  end

  def key(type, _data) when type in @keys, do: type
  def key(_type, _data), do: nil
end
