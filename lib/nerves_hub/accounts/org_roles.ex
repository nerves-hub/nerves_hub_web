defmodule NervesHub.Accounts.OrgRoles do
  @moduledoc """
  Context for the roles an organization defines for itself.

  See `NervesHub.Accounts.OrgRole` for what a custom role is, and
  `NervesHub.Accounts.Permissions` for what it can grant.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Accounts.Invite
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Repo

  @doc """
  The org's custom roles, by name.
  """
  @spec list_org_roles(Org.t()) :: [OrgRole.t()]
  def list_org_roles(%Org{id: org_id}) do
    OrgRole
    |> where(org_id: ^org_id)
    |> Repo.exclude_deleted()
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  One of the org's custom roles.
  """
  @spec get_org_role(Org.t(), integer() | String.t()) :: {:ok, OrgRole.t()} | {:error, :not_found}
  def get_org_role(%Org{id: org_id}, id), do: fetch_org_role(org_id, id)

  defp fetch_org_role(org_id, id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} ->
        OrgRole
        |> where(org_id: ^org_id, id: ^id)
        |> Repo.exclude_deleted()
        |> Repo.fetch()

      :error ->
        {:error, :not_found}
    end
  end

  @spec change_org_role(OrgRole.t(), map()) :: Changeset.t()
  def change_org_role(%OrgRole{} = role, params \\ %{}) do
    OrgRole.changeset(role, params)
  end

  @spec create_org_role(Org.t(), map()) :: {:ok, OrgRole.t()} | {:error, Changeset.t()}
  def create_org_role(%Org{id: org_id}, params) do
    %OrgRole{org_id: org_id}
    |> OrgRole.changeset(params)
    |> Repo.insert()
  end

  @doc """
  Changes a custom role's name, description or permissions.

  Members holding the role get the new permissions the next time they load a
  page; one they already have open keeps the old ones until then.
  """
  @spec update_org_role(OrgRole.t(), map()) :: {:ok, OrgRole.t()} | {:error, Changeset.t()}
  def update_org_role(%OrgRole{} = role, params) do
    role
    |> OrgRole.changeset(params)
    |> Repo.update()
  end

  @doc """
  Deletes a custom role nobody uses.

  Returns `{:error, :in_use}` while a member holds the role or an outstanding
  invite offers it. Deleting it then would quietly change what those people
  can do, so they have to be moved to another role first.
  """
  @spec delete_org_role(OrgRole.t()) :: {:ok, OrgRole.t()} | {:error, :in_use} | {:error, Changeset.t()}
  def delete_org_role(%OrgRole{} = role) do
    Repo.transact(fn ->
      if in_use?(role) do
        {:error, :in_use}
      else
        Repo.soft_delete(role)
      end
    end)
  end

  @doc """
  How many members hold each role in the org.

  Keyed by built-in role (`:admin`, `:manage`, `:view`) and by custom role id.
  A role nobody holds is missing from the map.
  """
  @spec member_counts(Org.t()) :: %{(atom() | integer()) => non_neg_integer()}
  def member_counts(%Org{id: org_id}) do
    org_id
    |> active_members()
    |> group_by([ou], [ou.role, ou.org_role_id])
    |> select([ou], {ou.role, ou.org_role_id, count()})
    |> Repo.all()
    |> Map.new(fn {role, org_role_id, count} -> {org_role_id || role, count} end)
  end

  @doc """
  Adds an error to a member or invite changeset whose `org_role_id` isn't one of
  the custom roles of the org it's for.

  The database already refuses another organization's role. This also refuses
  one that has been deleted.
  """
  @spec validate_org_role(Changeset.t()) :: Changeset.t()
  def validate_org_role(changeset) do
    org_id = Changeset.get_field(changeset, :org_id)

    Changeset.validate_change(changeset, :org_role_id, fn :org_role_id, org_role_id ->
      case fetch_org_role(org_id, org_role_id) do
        {:ok, _role} -> []
        {:error, :not_found} -> [org_role_id: "is not a role in this organization"]
      end
    end)
  end

  defp in_use?(%OrgRole{id: id, org_id: org_id}) do
    held? =
      org_id
      |> active_members()
      |> where([ou], ou.org_role_id == ^id)
      |> Repo.exists?()

    # Unaccepted rather than pending: an expired invite can still be resent,
    # and would come back offering a role that no longer exists.
    offered? =
      Invite
      |> where(org_id: ^org_id, org_role_id: ^id, accepted: false)
      |> where([i], is_nil(i.declined_at))
      |> Repo.exists?()

    held? or offered?
  end

  defp active_members(org_id) do
    OrgUser
    |> where(org_id: ^org_id)
    |> join(:inner, [ou], u in assoc(ou, :user))
    |> where([ou, u], is_nil(ou.deleted_at) and is_nil(u.deleted_at))
  end
end
