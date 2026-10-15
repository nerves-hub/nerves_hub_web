defmodule NervesHub.Integrations.Teams.PendingEvent do
  @moduledoc """
  An event waiting to be posted to a Teams channel. Events are held for a few
  seconds so that a burst goes out as one card
  (`NervesHub.Workers.PostTeamsEvents`). `data` is the event's data as
  `NervesHub.Integrations.dispatch/3` built it, and so has string keys once
  read back.
  """
  use Ecto.Schema

  alias NervesHub.Integrations.Teams.Channel

  @type t :: %__MODULE__{}

  schema "teams_pending_events" do
    belongs_to(:channel, Channel)

    field(:type, :string)
    field(:data, :map)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end
end
