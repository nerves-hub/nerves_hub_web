defmodule NervesHub.Workers.QueueStrandedChatEvents do
  @moduledoc """
  Queues a posting job for each Slack subscription and chat webhook (Teams
  and Discord) holding events that no job is coming for
  (`NervesHub.Integrations.Slack.Subscriptions.queue_stranded/0`,
  `NervesHub.Integrations.ChatWebhooks.queue_stranded/0`). Runs every minute, so
  such events go out a minute or so late rather than waiting for the
  channel's next event.
  """

  # The next minute's run is the retry.
  use Oban.Worker,
    queue: :cleanup,
    max_attempts: 1,
    unique: [states: :incomplete]

  alias NervesHub.Integrations.ChatWebhooks
  alias NervesHub.Integrations.Slack.Subscriptions

  @impl Oban.Worker
  def perform(_job) do
    _ = Subscriptions.queue_stranded()
    _ = ChatWebhooks.queue_stranded()

    :ok
  end
end
