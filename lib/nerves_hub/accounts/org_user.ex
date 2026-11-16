defmodule NervesHub.Accounts.OrgUser do
  use Ecto.Schema

  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.User

  @type t :: %__MODULE__{}

  schema "org_users" do
    belongs_to(:org, Org, where: [deleted_at: nil])
    belongs_to(:user, User, where: [deleted_at: nil])

    # A member holds a built-in `role` or a custom `org_role`, never both.
    belongs_to(:org_role, OrgRole, where: [deleted_at: nil])
    field(:role, Ecto.Enum, values: [:admin, :manage, :view])
    field(:deleted_at, :utc_datetime)

    timestamps()
  end

  def with_user(query) do
    preload(query, :user)
  end

  @doc """
  The role a member holds: a built-in role, or their custom `OrgRole`.

  A custom role must be preloaded. One that has since been deleted comes back
  as `nil`, which grants nothing.
  """
  @spec assigned_role(t()) :: :admin | :manage | :view | OrgRole.t() | nil
  def assigned_role(%__MODULE__{org_role_id: nil, role: role}), do: role

  def assigned_role(%__MODULE__{org_role: %Ecto.Association.NotLoaded{}}) do
    raise ArgumentError, "the member's custom role must be preloaded to know what it grants"
  end

  def assigned_role(%__MODULE__{org_role: org_role}), do: org_role
end
