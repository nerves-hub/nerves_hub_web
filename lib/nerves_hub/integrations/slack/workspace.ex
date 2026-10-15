defmodule NervesHub.Integrations.Slack.Workspace do
  @moduledoc """
  A Slack workspace NervesHub's Slack app is installed in.

  Slack issues one bot token per workspace, however many times the app is
  installed there, so the token lives here rather than on each
  organization's `NervesHub.Integrations.Slack.Connection`. It is encrypted at rest
  (`NervesHub.Types.Encrypted`).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Integrations.Slack.Connection
  alias NervesHub.Types.Encrypted

  @type t :: %__MODULE__{}

  schema "slack_workspaces" do
    has_many(:connections, Connection)

    field(:team_id, :string)
    field(:team_name, :string)
    field(:enterprise_id, :string)
    field(:app_id, :string)
    field(:bot_user_id, :string)
    field(:bot_token, Encrypted, redact: true)
    field(:scopes, {:array, :string}, default: [])

    timestamps()
  end

  @doc """
  The workspace as an OAuth exchange described it: new, or the existing one
  with a fresh token and scopes.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = workspace, attrs) do
    workspace
    |> cast(attrs, [:team_id, :team_name, :enterprise_id, :app_id, :bot_user_id, :bot_token, :scopes])
    |> validate_required([:team_id, :team_name, :app_id, :bot_user_id, :bot_token])
    |> unique_constraint(:team_id)
  end
end
