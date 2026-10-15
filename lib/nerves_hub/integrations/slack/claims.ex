defmodule NervesHub.Integrations.Slack.Claims do
  @moduledoc """
  Keeps something done from Slack from being done twice.

  A claim is a key held until it expires. `claim/3` takes it if nobody holds
  it, and says who does if somebody does. It is one statement in Postgres, so
  two requests racing on different web nodes cannot both take it.

  Two kinds of key are claimed:

    * a request Slack sent, by its `trigger_id`, so a signed request replayed
      within the five minutes its signature lasts is not acted on again,
    * a device asked to reboot, so a double click, two people clicking at
      once, or a button and a command together reboot it once.
  """

  import Ecto.Query

  alias NervesHub.Repo

  defmodule Claim do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:key, :string, autogenerate: false}
    schema "slack_claims" do
      field(:holder, :string)
      field(:expires_at, :utc_datetime_usec)
    end
  end

  # Expired claims are swept as new ones are made. Anything older than this
  # past its expiry goes.
  @sweep_after_seconds 3600

  @doc """
  Takes `key` for `seconds`, naming `holder`. Returns `:ok` when it was free,
  or `{:held, holder, expires_at}` when somebody holds it.
  """
  @spec claim(String.t(), pos_integer(), String.t() | nil) :: :ok | {:held, String.t() | nil, DateTime.t()}
  def claim(key, seconds, holder \\ nil) do
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, seconds)

    _ = sweep(now)

    # Inserts, or takes over a claim that has expired; an unexpired claim is
    # left alone, and the insert returns nothing.
    {count, _} =
      Repo.insert_all(
        Claim,
        [%{key: key, holder: holder, expires_at: expires_at}],
        on_conflict:
          from(c in Claim,
            where: c.expires_at <= ^now,
            update: [set: [holder: ^holder, expires_at: ^expires_at]]
          ),
        conflict_target: :key
      )

    if count == 1 do
      :ok
    else
      Claim
      |> where(key: ^key)
      |> select([c], {c.holder, c.expires_at})
      |> Repo.one()
      |> case do
        {holder, expires_at} -> {:held, holder, expires_at}
        # Released between the two statements, which is as good as free.
        nil -> :ok
      end
    end
  end

  defp sweep(now) do
    cutoff = DateTime.add(now, -@sweep_after_seconds)
    Claim |> where([c], c.expires_at < ^cutoff) |> Repo.delete_all()
  end
end
