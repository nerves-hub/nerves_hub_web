defmodule NervesHub.Integrations.Slack.Connection do
  @moduledoc """
  An organization connected to a Slack workspace, by a member who installed
  NervesHub's Slack app there on the organization's behalf.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.User
  alias NervesHub.Integrations.Slack.Subscription
  alias NervesHub.Integrations.Slack.Workspace

  @type t :: %__MODULE__{}

  schema "slack_connections" do
    belongs_to(:org, Org)
    belongs_to(:workspace, Workspace)
    belongs_to(:connected_by, User)

    has_many(:subscriptions, Subscription, preload_order: [asc: :inserted_at, asc: :id])

    timestamps()
  end

  @spec create_changeset(Org.t(), Workspace.t(), User.t()) :: Ecto.Changeset.t()
  def create_changeset(%Org{} = org, %Workspace{} = workspace, %User{} = user) do
    %__MODULE__{org_id: org.id, workspace_id: workspace.id, connected_by_id: user.id}
    |> change()
    |> unique_constraint([:org_id, :workspace_id])
    |> foreign_key_constraint(:org_id)
  end
end
