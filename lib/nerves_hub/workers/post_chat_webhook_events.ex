defmodule NervesHub.Workers.PostChatWebhookEvents do
  @moduledoc """
  Posts the events held for one chat webhook's channel. Queued by
  `NervesHub.Integrations.ChatWebhooks.queue_events/3`, a few seconds after the
  first event, so that the ones that follow are posted with it.

  Unique per channel while waiting to run, so a burst of events queues
  one job; once a job is running, the next event queues the next.

  The chat service asking NervesHub to wait, and failing, are snoozes rather than
  errors, for the reason `NervesHub.Workers.DeliverWebhook` gives: Sentry
  reports every job that returns an error, and a chat service being down is not a
  fault in NervesHub. A failure is retried after 10 seconds, a minute and five
  minutes. After that the job stops, and what it could not post waits for the
  channel's next event, or is dropped once it is an hour old.
  """

  use Oban.Worker,
    queue: :chat_webhooks,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:chat_webhook_id], states: [:available, :scheduled]]

  alias NervesHub.Integrations.ChatWebhooks

  @retry_delays_seconds [10, 60, 300]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"chat_webhook_id" => id}} = job) do
    case ChatWebhooks.post_pending_events(id) do
      :ok -> :ok
      {:rate_limited, seconds} -> {:snooze, seconds}
      {:cancel, reason} -> {:cancel, reason}
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
