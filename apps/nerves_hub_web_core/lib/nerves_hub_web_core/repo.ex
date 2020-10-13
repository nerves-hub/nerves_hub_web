defmodule NervesHubWebCore.Repo do
  use Ecto.Repo,
    otp_app: :nerves_hub_web_core,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Dynamically loads the following parameters with environment variables:
    url <= DATABASE_URL
    pool_size <= DATABASE_POOL_SIZE
    prepare <= DATABASE_PREPARED_STATEMENT
  """
  def init(_, opts) do
    config = 
      with  url <- System.get_env("DATABASE_URL"),
            pool_size <- System.get_env("DATABASE_POOL_SIZE") || "20",
            pool_size_int <- String.to_integer(pool_size),
            prepared_statements <- System.get_env("DATABASE_PREPARED_STATEMENT") || "named",
            prepared_statements_atom <- String.to_existing_atom(prepared_statements) do
        opts
        |> Keyword.put(:url, url)
        |> Keyword.put(:pool_size, pool_size_int)
        |> Keyword.put(:prepare, prepared_statements_atom)
      end

    {:ok, config}
  end

  def reload(%module{id: id}), do: get(module, id)

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
end
