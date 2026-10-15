defmodule NervesHub.Integrations.Slack.UserLink do
  @moduledoc """
  A Slack user, in one workspace, linked to a NervesHub user. What they do
  with NervesHub's buttons in Slack is done as that NervesHub user, with that
  user's permissions as they stand at the time (`NervesHub.Integrations.Slack.Actions`).

  Made only by the NervesHub user signing in with Slack as that Slack user
  (`NervesHub.Integrations.Slack.Users`).
  """
  use Ecto.Schema

  alias NervesHub.Accounts.User

  @type t :: %__MODULE__{}

  schema "slack_user_links" do
    belongs_to(:user, User)

    field(:team_id, :string)
    field(:slack_user_id, :string)
    field(:slack_name, :string)
    field(:team_name, :string)
    field(:linked_at, :utc_datetime_usec)
    field(:last_used_at, :utc_datetime_usec)

    timestamps()
  end
end
