defmodule NervesHub.Accounts.OrgRole do
  @moduledoc """
  A role an organization defines for itself, alongside the built-in admin,
  manage and view roles.

  A custom role is a name and a list of permissions picked from
  `NervesHub.Accounts.Permissions.custom_role_options/0`. A member holds either
  a built-in role or a custom one, never both.

  A custom role can also be limited to devices with certain tags, matched the
  way deployment groups match them: all of the tags (`:and`), or any of them
  (`:or`). Its members only see those devices, and it can only be given
  `NervesHub.Accounts.Permissions.device_permissions/0`. See
  `NervesHub.Devices.Visibility`.

  Custom roles are soft deleted, so the members and invites that once used one
  keep pointing at a row. A role can only be deleted once nobody holds it and
  no outstanding invite offers it.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.Permissions
  alias NervesHub.Types.Tag

  @type t :: %__MODULE__{}

  schema "org_roles" do
    belongs_to(:org, Org)

    field(:name, :string)
    field(:description, :string)
    field(:permissions, {:array, :string}, default: [])
    field(:device_tags, Tag, default: [])
    field(:device_tag_operator, Ecto.Enum, values: [:and, :or], default: :and)
    field(:deleted_at, :utc_datetime)

    timestamps()
  end

  @doc """
  Validates a new or edited custom role.
  """
  def changeset(%__MODULE__{} = role, params) do
    role
    |> cast(params, [:name, :description, :permissions, :device_tags, :device_tag_operator], empty_values: [nil])
    |> update_change(:name, &String.trim/1)
    |> update_change(:description, &blank_to_nil/1)
    |> update_change(:permissions, &normalize_permissions/1)
    |> update_change(:device_tags, &Enum.uniq/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 50)
    |> validate_length(:description, max: 255)
    |> validate_not_built_in()
    |> validate_subset(:permissions, Permissions.custom_role_options())
    |> validate_device_permissions()
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

  @doc """
  Whether the role only sees devices with certain tags.
  """
  @spec limited_to_tags?(t()) :: boolean()
  def limited_to_tags?(%__MODULE__{device_tags: tags}), do: tags != []

  # A member who sees some of the org's devices can't be trusted with anything
  # that acts on the rest, like a deployment group or the product itself.
  defp validate_device_permissions(changeset) do
    tags = get_field(changeset, :device_tags)
    permissions = get_field(changeset, :permissions)

    if tags != [] and not Enum.all?(permissions, &(&1 in Permissions.device_permissions())) do
      add_error(changeset, :permissions, "can only act on single devices when the role is limited to tagged devices")
    else
      changeset
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(string) do
    case String.trim(string) do
      "" -> nil
      trimmed -> trimmed
    end
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
