defmodule NervesHub.Integrations.Slack.ScriptResults do
  @moduledoc """
  Support script output run from Slack, kept so whoever ran it can share it
  in the channel.

  Slack shows the output only to whoever ran the script, and a button can
  carry at most 2,000 characters, too few for the output. So the output is
  kept here, the Share button carries its id, and sharing takes it out.
  Output is kept for 30 minutes, as long as Slack lets NervesHub answer the
  command, and is swept away after that whether it was shared or not.
  """

  import Ecto.Query

  alias NervesHub.Accounts.User
  alias NervesHub.Repo

  @keep_seconds 1800

  defmodule ScriptResult do
    @moduledoc false
    use Ecto.Schema

    @type t :: %__MODULE__{}

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "slack_script_results" do
      belongs_to(:user, User)

      field(:team_id, :string)
      field(:slack_user_id, :string)
      field(:device_identifier, :string)
      field(:script_name, :string)
      field(:output, :string)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end
  end

  @doc "Keeps a script's output for sharing. Returns its id."
  @spec store(map()) :: String.t()
  def store(attrs) do
    :ok = sweep()
    struct(ScriptResult, attrs) |> Repo.insert!() |> Map.fetch!(:id)
  end

  @doc """
  Takes the output to share, if it is still kept and `slack_user_id` in
  `team_id` is who ran it. Taking it removes it, so it is shared once.
  """
  @spec take(String.t(), String.t(), String.t()) :: {:ok, ScriptResult.t()} | {:error, :gone | :not_yours}
  def take(id, team_id, slack_user_id) do
    :ok = sweep()

    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        # One statement, so two clicks at once cannot both share it.
        ScriptResult
        |> where(id: ^id, team_id: ^team_id, slack_user_id: ^slack_user_id)
        |> select([r], r)
        |> Repo.delete_all()
        |> case do
          {1, [result]} -> {:ok, result}
          {0, []} -> if Repo.exists?(where(ScriptResult, id: ^id)), do: {:error, :not_yours}, else: {:error, :gone}
        end

      :error ->
        {:error, :gone}
    end
  end

  defp sweep() do
    cutoff = DateTime.add(DateTime.utc_now(), -@keep_seconds)
    {_count, _} = ScriptResult |> where([r], r.inserted_at < ^cutoff) |> Repo.delete_all()
    :ok
  end
end
