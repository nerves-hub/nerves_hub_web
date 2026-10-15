defmodule NervesHub.Workers.UpdateSlackWorkflowMessage do
  @moduledoc """
  Edits a Slack message with buttons for workflow steps, to say what happened
  to them (`NervesHub.Integrations.Slack.WorkflowMessages`). Queued as soon
  as a step is dealt with.

  Unique per message while waiting to run, so steps dealt with together
  edit it once.

  Slack asking NervesHub to wait, and Slack failing, are snoozes rather than
  errors, for the reason `NervesHub.Workers.DeliverWebhook` gives. A failure
  is retried after 10 seconds, a minute and five minutes, and then left: the
  message keeps its buttons, and a click on one still checks the step.
  """

  use Oban.Worker,
    queue: :slack,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:workflow_message_id], states: [:available, :scheduled]]

  alias NervesHub.Integrations.Slack.WorkflowMessages

  @retry_delays_seconds [10, 60, 300]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"workflow_message_id" => id}} = job) do
    case WorkflowMessages.update(id) do
      :ok -> :ok
      {:rate_limited, seconds} -> {:snooze, seconds}
      {:error, message} -> retry(failed_attempts(job), message)
    end
  end

  defp retry(failed_attempts, _message) when failed_attempts < length(@retry_delays_seconds) do
    {:snooze, Enum.at(@retry_delays_seconds, failed_attempts)}
  end

  defp retry(failed_attempts, message) do
    {:cancel, "gave up after #{failed_attempts + 1} attempts: #{message}"}
  end

  defp failed_attempts(%Oban.Job{meta: meta}), do: Map.get(meta, "snoozed", 0)
end
