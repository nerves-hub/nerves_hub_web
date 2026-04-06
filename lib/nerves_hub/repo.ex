defmodule NervesHub.Repo do
  use Ecto.Repo,
    otp_app: :nerves_hub,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query, only: [where: 3]

  @type transaction ::
          {:ok, any()}
          | {:error, any()}
          | {:error, Ecto.Multi.name(), any(), %{required(Ecto.Multi.name()) => any()}}

  def reload_assoc({:ok, schema}, assoc) do
    schema =
      case Map.get(schema, assoc) do
        %Ecto.Association.NotLoaded{} ->
          schema

        _ ->
          preload(schema, assoc, force: true)
      end

    {:ok, schema}
  end

  def reload_assoc({:error, changeset}, _), do: {:error, changeset}

  def maybe_preload({:ok, entity}, assocs) do
    {:ok, preload(entity, assocs)}
  end

  def maybe_preload({:error, _} = result, _assocs) do
    result
  end

  def soft_delete(struct_or_changeset) do
    struct_or_changeset
    |> soft_delete_changeset()
    |> update()
  end

  def soft_delete_changeset(struct_or_changeset) do
    deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

    Ecto.Changeset.change(struct_or_changeset, deleted_at: deleted_at)
  end

  def exclude_deleted(query) do
    where(query, [o], is_nil(o.deleted_at))
  end

  def destroy(struct_or_changeset), do: delete(struct_or_changeset)

  # AshPostgres compatibility callbacks
  def installed_extensions, do: []
  def tenant_migrations_path, do: nil
  def migrations_path, do: nil
  def create_schemas_in_migrations?, do: true
  def default_prefix, do: "public"
  def override_migration_type(type), do: type
  def use_builtin_uuidv7_function?, do: false
  def create?, do: true
  def drop?, do: true
  def disable_atomic_actions?, do: false
  def disable_expr_error?, do: false
  def immutable_expr_error?, do: false
  def prefer_transaction?, do: true
  def prefer_transaction_for_atomic_updates?, do: false
  def default_constraint_match_type(_type, _name), do: :exact
  def on_transaction_begin(_reason), do: :ok

  def min_pg_version do
    %Version{major: 14, minor: 0, patch: 0}
  end

  def all_tenants do
    raise "all_tenants/0 not implemented"
  end

  def transaction!(fun) do
    case fun.() do
      {:ok, value} -> value
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end
end
