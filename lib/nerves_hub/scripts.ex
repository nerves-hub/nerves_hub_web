defmodule NervesHub.Scripts do
  import Ecto.Query

  alias Ecto.Changeset
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.Filtering, as: CommonFiltering
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Scripts.Script

  @spec filter(Scope.t() | Product.t(), map()) :: {[Script.t()], Flop.Meta.t()}
  def filter(scope_or_product, opts \\ %{})

  def filter(%Scope{product: product}, opts) do
    filter(product, opts)
  end

  def filter(%Product{} = product, opts) do
    Script
    |> from()
    |> add_last_editor_name()
    |> CommonFiltering.filter(
      product,
      opts
    )
  end

  def all_by_product(product) do
    Script
    |> where([c], c.product_id == ^product.id)
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  Returns the sorted, distinct list of tags used by all scripts in a product.

  Used to power tag autocomplete suggestions when creating or editing scripts.
  """
  @spec distinct_tags_for_product(Product.t()) :: [String.t()]
  def distinct_tags_for_product(%Product{} = product) do
    Script
    |> where([s], s.product_id == ^product.id)
    |> select([s], s.tags)
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  def get!(id) do
    Repo.get!(Script, id)
  end

  def get_by_id!(%Scope{product: product}, id) do
    Script
    |> where([s], s.id == ^id and s.product_id == ^product.id)
    |> add_last_editor_name()
    |> Repo.one!()
  end

  defp add_last_editor_name(query) do
    query
    |> join(:left, [s], lub in assoc(s, :last_updated_by), as: :last_updated_by)
    |> join(:left, [s], cb in assoc(s, :created_by), as: :created_by)
    |> select_merge([s, last_updated_by: lub, created_by: cb], %{
      last_editor_name: selected_as(fragment("COALESCE(?, ?)", lub.name, cb.name), :last_editor_name)
    })
  end

  def get_by_product_and_id!(product, id) do
    Repo.get_by!(Script, id: id, product_id: product.id)
  end

  def get(%Product{} = product, id) when is_integer(id) do
    Script
    |> where([c], c.id == ^id and c.product_id == ^product.id)
    |> join(:left, [s], cb in assoc(s, :created_by))
    |> preload([s, cb], created_by: cb)
    |> Repo.fetch()
  end

  def get(_, _) do
    {:error, :not_found}
  end

  def get_by_product_and_name(product, name) do
    case Repo.get_by(Script, name: name, product_id: product.id) do
      nil ->
        {:error, :not_found}

      script ->
        {:ok, script}
    end
  end

  def get_by_product_and_name_with_id_fallback(product, name_or_id) do
    # Try to find by name first
    case get_by_product_and_name(product, name_or_id) do
      {:ok, script} ->
        {:ok, script}

      {:error, :not_found} ->
        # If not found by name, try by ID
        case Integer.parse(name_or_id) do
          {id, ""} -> get(product, id)
          _ -> {:error, :not_found}
        end
    end
  end

  @spec create(Product.t(), User.t(), map()) :: {:ok, Script.t()} | {:error, Changeset.t()}
  def create(product, user, params) do
    Script.create_changeset(product, user, params)
    |> Repo.insert()
    |> case do
      {:ok, script} ->
        ProductTemplates.audit_script_created(user, product, script)
        {:ok, script}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec update(Script.t(), User.t(), map()) :: {:ok, Script.t()} | {:error, Changeset.t()}
  def update(script, user, params) do
    script
    |> Script.update_changeset(user, params)
    |> Repo.update()
    |> case do
      {:ok, script} ->
        product = Products.get_product!(script.product_id)

        ProductTemplates.audit_script_updated(user, product, script)

        {:ok, script}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec delete(non_neg_integer(), Product.t(), User.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def delete(id, product, user) do
    get_by_product_and_id!(product, id)
    |> Repo.delete()
    |> case do
      {:ok, script} ->
        ProductTemplates.audit_script_deleted(user, product, script)

        {:ok, script}

      err ->
        err
    end
  end
end
