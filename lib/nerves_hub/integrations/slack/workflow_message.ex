defmodule NervesHub.Integrations.Slack.WorkflowMessage do
  @moduledoc """
  A Slack message with buttons for deployment workflow steps (Approve, or
  Retry and Skip), kept so that it can be edited once the steps are dealt
  with (`NervesHub.Integrations.Slack.WorkflowMessages`).

  `events` is what the message was built from, so it can be built again;
  `step_ids` are the steps it has buttons for. `resolutions` says, by step id
  (as a string, since it is JSON), what happened to each step that has been
  dealt with: `%{"change" => "approved", "by" => "Alice"}`, or
  `%{"change" => "replaced", "release" => 5}` for a step a new release left
  behind.
  """
  use Ecto.Schema

  alias NervesHub.Integrations.Slack.Subscription

  @type t :: %__MODULE__{}

  schema "slack_workflow_messages" do
    belongs_to(:subscription, Subscription)

    field(:channel_id, :string)
    field(:ts, :string)
    field(:type, :string)
    field(:events, {:array, :map})
    field(:step_ids, {:array, :integer})
    field(:resolutions, :map, default: %{})

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end
end
