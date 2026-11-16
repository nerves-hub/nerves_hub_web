defmodule NervesHub.Devices.Visibility do
  @moduledoc """
  Which devices a user can see.

  A member with a built-in role, or with a custom role that isn't limited to
  tagged devices, sees every device in the org. A custom role limited to tags
  (`NervesHub.Accounts.OrgRole`) sees only the devices those tags match, the
  way deployment groups match them: all of the role's tags, or any of them.

  The check runs in the database, against the member's role as it is when the
  query runs. It needs nothing from the caller but the user, so a query across
  several orgs gets each org's role right, and a caller can't skip it by
  handing over a scope that lacks some field.
  """

  import Ecto.Query

  alias NervesHub.Accounts.User

  @doc """
  Limits a device query to the devices `user` can see.

  The devices must be the query's first binding.
  """
  @spec where_visible(Ecto.Queryable.t(), User.t()) :: Ecto.Query.t()
  def where_visible(query, %User{id: user_id}) do
    # A member whose custom role has since been deleted matches no role row,
    # and sees nothing.
    where(
      query,
      [d],
      fragment(
        """
        EXISTS (
          SELECT 1
          FROM org_users AS ou
          LEFT JOIN org_roles AS r ON r.id = ou.org_role_id AND r.deleted_at IS NULL
          WHERE ou.org_id = ?
            AND ou.user_id = ?
            AND ou.deleted_at IS NULL
            AND (
              (ou.org_role_id IS NULL AND ou.role IS NOT NULL)
              OR cardinality(r.device_tags) = 0
              OR (r.device_tag_operator = 'and' AND r.device_tags::text[] <@ ?::text[])
              OR (r.device_tag_operator = 'or' AND r.device_tags::text[] && ?::text[])
            )
        )
        """,
        d.org_id,
        ^user_id,
        d.tags,
        d.tags
      )
    )
  end
end
