defmodule NervesHub.Accounts.Starring do
  @moduledoc """
  The organizations each user has starred.

  Someone who belongs to five or more organizations stars the ones they want
  in full on their home page (`NervesHubWeb.Live.Orgs.Index`). The rest share
  a compact table there.

  A star is the user's own: nobody else in the organization sees it, and it
  goes when they leave the organization.
  """

  import Ecto.Query

  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.StarredOrg
  alias NervesHub.Repo

  @doc """
  The ids of the organizations the scope's user has starred.

  Stars on organizations that have since been deleted are still here, so
  check an id against the organizations the user can see before using it.
  """
  @spec starred_org_ids(Scope.t()) :: MapSet.t(pos_integer())
  def starred_org_ids(%Scope{user: user}) when not is_nil(user) do
    StarredOrg
    |> where(user_id: ^user.id)
    |> select([s], s.org_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Stars the organization for the user. Starring one that's already starred
  does nothing.

  The caller checks the user belongs to the organization.
  """
  @spec star_org(pos_integer(), pos_integer()) :: :ok | {:error, Ecto.Changeset.t()}
  def star_org(user_id, org_id) do
    %{user_id: user_id, org_id: org_id}
    |> StarredOrg.create()
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :org_id])
    |> case do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Unstars the organization for the user. Unstarring one that isn't starred
  does nothing.
  """
  @spec unstar_org(pos_integer(), pos_integer()) :: {non_neg_integer(), nil}
  def unstar_org(user_id, org_id) do
    StarredOrg
    |> where(user_id: ^user_id, org_id: ^org_id)
    |> Repo.delete_all()
  end
end
