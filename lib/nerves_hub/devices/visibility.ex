defmodule NervesHub.Devices.Visibility do
  @moduledoc """
  Which devices a user, or a product API key, can see.

  A member with a built-in role, or with a custom role that isn't limited to
  tagged devices, sees every device in the org. A custom role limited to tags
  (`NervesHub.Accounts.OrgRole`) sees only the devices those tags match, the
  way deployment groups match them: all of the role's tags, or any of them.

  A product API key holds a role the same way, so the same rules decide what
  it sees. Its own routes already keep it to one product; this is what keeps a
  key whose role is limited to tags from seeing the rest of that product.

  The check runs in the database, against the role as it is when the query
  runs. It needs nothing from the caller but the user or the key, so a query
  across several orgs gets each org's role right, and a caller can't skip it by
  handing over a scope that lacks some field.
  """

  import Ecto.Query

  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.Products.ApiKey

  @doc """
  Limits a device query to the devices `subject` can see: a user, a product API
  key, or the scope of whichever is acting.

  The devices must be the query's first binding.
  """
  @spec where_visible(Ecto.Queryable.t(), User.t() | ApiKey.t() | Scope.t()) :: Ecto.Query.t()
  def where_visible(query, %Scope{} = scope), do: where_visible(query, Scope.actor(scope))

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

  def where_visible(query, %ApiKey{id: api_key_id}) do
    # A key whose custom role has since been deleted matches no role row, and
    # sees nothing.
    where(
      query,
      [d],
      fragment(
        """
        EXISTS (
          SELECT 1
          FROM product_api_keys AS k
          LEFT JOIN org_roles AS r ON r.id = k.org_role_id AND r.deleted_at IS NULL
          WHERE k.id = ?
            AND k.deactivated_at IS NULL
            AND (
              (k.org_role_id IS NULL AND k.role IS NOT NULL)
              OR cardinality(r.device_tags) = 0
              OR (r.device_tag_operator = 'and' AND r.device_tags::text[] <@ ?::text[])
              OR (r.device_tag_operator = 'or' AND r.device_tags::text[] && ?::text[])
            )
        )
        """,
        ^api_key_id,
        d.tags,
        d.tags
      )
    )
  end
end
