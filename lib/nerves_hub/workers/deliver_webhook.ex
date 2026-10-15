defmodule NervesHub.Workers.DeliverWebhook do
  @moduledoc """
  Delivers one event to one webhook. Queued by `NervesHub.Webhooks.dispatch/3`.

  The webhook is read when the job runs, not when it was queued, so a delivery
  goes to the current URL, is signed with the current secret, and is dropped
  if the webhook has since been deleted or turned off.

  ## Retries

  A failed attempt is retried after 5 seconds, 1 minute, 5 minutes, 30 minutes
  and 2 hours, each with up to a tenth more as jitter: six attempts over about
  two and a half hours, after which the delivery is given up and the job
  cancelled with the last error.

  The retries are snoozes rather than errors. A receiver refusing a delivery
  is not a fault in NervesHub, and Sentry's Oban integration reports every job
  that returns an error, so one broken receiver would bury real faults. Faults
  in this code still raise, are still reported, and still use Oban's own
  attempts. Delivery attempts are counted from the snooze count Oban keeps in
  the job's meta.

  The schedule is shorter than the days the Standard Webhooks specification
  suggests, because most of these events are telemetry a fleet sends
  constantly. Days of retries for an endpoint that is down would mean days of
  its deliveries piling up in the jobs table, for readings that are stale long
  before they arrive.
  """

  use Oban.Worker, queue: :webhooks, max_attempts: 3

  alias NervesHub.Webhooks
  alias NervesHub.Webhooks.Delivery

  @retry_delays_seconds [5, 60, 300, 1800, 7200]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_id" => webhook_id, "event_id" => event_id, "body" => body}} = job) do
    case Webhooks.deliverable_webhook(webhook_id) do
      nil -> {:cancel, "the webhook was deleted or turned off"}
      webhook -> attempt(webhook, event_id, body, failed_attempts(job))
    end
  end

  defp attempt(webhook, event_id, body, failed_attempts) do
    if Webhooks.cooling_down?(webhook, DateTime.utc_now()) do
      retry(failed_attempts, "not sent, because the endpoint failed moments ago: #{webhook.last_error}")
    else
      case Delivery.deliver(webhook, event_id, body) do
        {:ok, _status} ->
          Webhooks.record_success(webhook)

        {:error, status, message} ->
          case Webhooks.record_failure(webhook, status, message) do
            :ok -> retry(failed_attempts, message)
            :disabled -> {:cancel, "the webhook was turned off: #{message}"}
          end
      end
    end
  end

  defp retry(failed_attempts, _message) when failed_attempts < length(@retry_delays_seconds) do
    delay = Enum.at(@retry_delays_seconds, failed_attempts)

    {:snooze, delay + :rand.uniform(max(div(delay, 10), 1))}
  end

  defp retry(failed_attempts, message) do
    {:cancel, "gave up after #{failed_attempts + 1} attempts: #{message}"}
  end

  defp failed_attempts(%Oban.Job{meta: meta}), do: Map.get(meta, "snoozed", 0)
end
