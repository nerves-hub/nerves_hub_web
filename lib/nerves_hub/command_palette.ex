defmodule NervesHub.CommandPalette do
  @moduledoc """
  Backs the CMD-K command palette: a small, scope-aware search across devices
  (by identifier), deployment groups (by name), and firmware (by uuid).

  The search is scoped by where the user currently is, derived from the
  `NervesHub.Accounts.Scope`:

    * inside a product -> that product only
    * inside an org (no product) -> all products in that org the user belongs to
    * on the dashboard (no org) -> every product across the user's orgs

  In every case results are limited to products the user is a member of, so the
  palette can never surface entities from orgs the user can't otherwise see.
  """

  import Ecto.Query

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Scope
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  @min_term_length 2
  @limit_per_group 5

  @type result_group :: %{
          devices: [map()],
          deployment_groups: [map()],
          firmware: [map()]
        }

  @doc """
  Search devices, deployment groups and firmware for `term`, scoped to `scope`.

  Returns a map with `:devices`, `:deployment_groups` and `:firmware` keys, each
  a list of maps carrying the org/product names needed to build links. Terms
  shorter than #{@min_term_length} characters return empty results.
  """
  @spec search(Scope.t(), String.t(), keyword()) :: result_group()
  def search(scope, term, opts \\ [])

  def search(%Scope{} = scope, term, opts) when is_binary(term) do
    term = String.trim(term)

    if String.length(term) < @min_term_length do
      empty()
    else
      limit = Keyword.get(opts, :limit, @limit_per_group)

      case scoped_product_ids(scope) do
        [] ->
          empty()

        product_ids ->
          %{
            devices: search_devices(product_ids, term, limit),
            deployment_groups: search_deployment_groups(product_ids, term, limit),
            firmware: search_firmware(product_ids, term, limit)
          }
      end
    end
  end

  def search(_scope, _term, _opts), do: empty()

  defp empty(), do: %{devices: [], deployment_groups: [], firmware: []}

  # Devices: identifier substring. Backed by the `devices_identifier_trgm_index`
  # GIN trigram index, so ILIKE '%...%' stays fast even across many products.
  defp search_devices(product_ids, term, limit) do
    Device
    |> where([d], d.product_id in ^product_ids)
    |> where([d], is_nil(d.deleted_at))
    |> where([d], ilike(d.identifier, ^"%#{term}%"))
    |> join(:inner, [d], p in assoc(d, :product), as: :product)
    |> join(:inner, [d, product: p], o in assoc(p, :org), as: :org)
    |> order_by([d], asc: d.identifier)
    |> limit(^limit)
    |> select([d, product: p, org: o], %{
      identifier: d.identifier,
      org_name: o.name,
      product_name: p.name
    })
    |> Repo.all()
  end

  # Deployment groups: name substring. The table is tiny per product so a
  # sequential scan on the ILIKE is fine (no trigram index on name).
  defp search_deployment_groups(product_ids, term, limit) do
    DeploymentGroup
    |> where([dg], dg.product_id in ^product_ids)
    |> where([dg], ilike(dg.name, ^"%#{term}%"))
    |> join(:inner, [dg], p in assoc(dg, :product), as: :product)
    |> join(:inner, [dg, product: p], o in assoc(p, :org), as: :org)
    |> order_by([dg], asc: dg.name)
    |> limit(^limit)
    |> select([dg, product: p, org: o], %{
      id: dg.id,
      name: dg.name,
      org_name: o.name,
      product_name: p.name
    })
    |> Repo.all()
  end

  # Firmware: uuid prefix match. A prefix (uuid LIKE 'abc%') can use the btree
  # `firmwares_product_id_uuid_index`; there is no trigram index on uuid.
  defp search_firmware(product_ids, term, limit) do
    Firmware
    |> where([f], f.product_id in ^product_ids)
    |> where([f], ilike(f.uuid, ^"#{term}%"))
    |> join(:inner, [f], p in assoc(f, :product), as: :product)
    |> join(:inner, [f, product: p], o in assoc(p, :org), as: :org)
    |> order_by([f], desc: f.inserted_at)
    |> limit(^limit)
    |> select([f, product: p, org: o], %{
      uuid: f.uuid,
      version: f.version,
      platform: f.platform,
      org_name: o.name,
      product_name: p.name
    })
    |> Repo.all()
  end

  # Product ids in scope, always constrained to products the user belongs to.
  defp scoped_product_ids(%Scope{product: %Product{id: id}}), do: [id]

  defp scoped_product_ids(%Scope{org: %{id: org_id}, user: %{id: user_id}}), do: user_product_ids(user_id, org_id)

  defp scoped_product_ids(%Scope{user: %{id: user_id}}), do: user_product_ids(user_id, nil)

  defp scoped_product_ids(_scope), do: []

  defp user_product_ids(user_id, org_id) do
    Product
    |> join(:inner, [p], ou in OrgUser, on: ou.org_id == p.org_id)
    |> where([p, ou], ou.user_id == ^user_id and is_nil(ou.deleted_at))
    |> where([p], is_nil(p.deleted_at))
    |> maybe_filter_org(org_id)
    |> select([p], p.id)
    |> Repo.all()
  end

  defp maybe_filter_org(query, nil), do: query
  defp maybe_filter_org(query, org_id), do: where(query, [p], p.org_id == ^org_id)
end
