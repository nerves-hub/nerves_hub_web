defmodule NervesHub.Accounts.OrgRole do
  @moduledoc """
  A role an organization defines for itself, alongside the built-in admin,
  manage and view roles.

  A custom role is a name and a list of permissions picked from
  `NervesHub.Accounts.Permissions.custom_role_options/0`. A member holds either
  a built-in role or a custom one, never both.

  Custom roles are soft deleted, so the members and invites that once used one
  keep pointing at a row. A role can only be deleted once nobody holds it and
  no outstanding invite offers it.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.Permissions

  @type t :: %__MODULE__{}

  schema "org_roles" do
    belongs_to(:org, Org)

    field(:name, :string)
    field(:description, :string)
    field(:permissions, {:array, :string}, default: [])
    field(:deleted_at, :utc_datetime)

    timestamps()
  end

  @doc """
  Validates a new or edited custom role.
  """
  def changeset(%__MODULE__{} = role, params) do
    role
    |> cast(params, [:name, :description, :permissions])
    |> update_change(:name, &String.trim/1)
    |> update_change(:permissions, &normalize_permissions/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 50)
    |> validate_length(:description, max: 255)
    |> validate_not_built_in()
    |> validate_subset(:permissions, Permissions.custom_role_options())
    |> unique_constraint(:name,
      name: :org_roles_org_id_name_index,
      message: "is already used by another role"
    )
  end

  @doc """
  Validates who a member or invite is given: a built-in `role` or a custom
  `org_role_id`, exactly one of the two.

  Used by the `NervesHub.Accounts.OrgUser` and `NervesHub.Accounts.Invite`
  changesets, which cast both fields.
  """
  def validate_assignment(changeset) do
    role = get_field(changeset, :role)
    org_role_id = get_field(changeset, :org_role_id)

    # Like `validate_required/2`, a role that failed to cast already has its error.
    changeset =
      cond do
        Keyword.has_key?(changeset.errors, :role) -> changeset
        is_nil(role) and is_nil(org_role_id) -> add_error(changeset, :role, "can't be blank")
        role && org_role_id -> add_error(changeset, :role, "can't be both a built-in and a custom role")
        true -> changeset
      end

    changeset
    |> foreign_key_constraint(:org_role_id)
    |> check_constraint(:role, name: "#{changeset.data.__meta__.source}_one_kind_of_role")
  end

  # The form posts an empty string so a role can be saved with nothing picked.
  defp normalize_permissions(permissions) do
    permissions
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # "Admin" as a custom role would read, everywhere a role is shown, as the
  # built-in role it isn't.
  defp validate_not_built_in(changeset) do
    validate_change(changeset, :name, fn :name, name ->
      built_in_names = Enum.map(Permissions.built_in_roles(), &Atom.to_string/1)

      if String.downcase(name) in built_in_names do
        [name: "is the name of a built-in role"]
      else
        []
      end
    end)
  end
end
