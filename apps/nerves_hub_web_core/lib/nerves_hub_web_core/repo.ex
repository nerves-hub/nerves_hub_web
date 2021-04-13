defmodule NervesHubWebCore.Repo do
  use Ecto.Repo,
    otp_app: :nerves_hub_web_core,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Dynamically loads the repository url from the
  DATABASE_URL environment variable.
  """
  def init(_, opts) do
    {:ok, Keyword.put(opts, :url, System.get_env("DATABASE_URL"))}
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
end
