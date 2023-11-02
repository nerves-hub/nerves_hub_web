defmodule NervesHub.Repo do
  use Ecto.Repo,
    otp_app: :nerves_hub,
    adapter: Ecto.Adapters.Postgres

  use Scrivener

  import Ecto.Query, only: [where: 3]

  @type transaction ::
          {:ok, any()}
          | {:error, any()}
          | {:error, Ecto.Multi.name(), any(), %{required(Ecto.Multi.name()) => any()}}

  @doc """
  Dynamically loads the repository url from the
  DATABASE_URL environment variable.
  """
  def init(_, config) do
    %{database: database_config} = NervesHub.Config.load!()
    merge_opts = Keyword.new(Map.take(database_config, [:pool_size, :url, :ssl]))
    config = Keyword.merge(config, merge_opts)

    config =
      case database_config.ipv6 do
        true -> Keyword.put(config, :socket_options, [:inet6])
        false -> config
      end

    {:ok, config}
  end

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
end

defmodule NervesHub.ObanRepo do
  use Ecto.Repo,
    otp_app: :nerves_hub,
    adapter: Ecto.Adapters.Postgres

  defdelegate init(context, config), to: NervesHub.Repo
end
