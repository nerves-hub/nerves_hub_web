defmodule NervesHub.Integrations.Slack.PendingEvent do
  @moduledoc """
  An event waiting to be posted to a subscription's channel. Events are held
  for a few seconds so that a burst goes out as one message
  (`NervesHub.Workers.PostSlackEvents`). `data` is the event's data as
  `NervesHub.Integrations.dispatch/3` built it, and so has string keys once
  read back.
  """
  use Ecto.Schema

  alias NervesHub.Integrations.Slack.Subscription

  @type t :: %__MODULE__{}

  schema "slack_pending_events" do
    belongs_to(:subscription, Subscription)

    field(:type, :string)
    field(:data, :map)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end
end
