defmodule NervesHub.Workers.ExpireInflightUpdates do
  @moduledoc """
  Expire inflight updates every 5 minutes

  Expiration is set from the deployment when the inflight update is recorded.
  """

  use Oban.Worker,
    max_attempts: 1,
    queue: :truncate

  import Ecto.Query

  require Logger

  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Repo

  @impl true
  def perform(_) do
    {count, _} =
      InflightUpdate
      |> where([iu], iu.expires_at < fragment("now()"))
      |> Repo.delete_all()

    if count > 0 do
      Logger.info("Expired #{count} inflight updates")
    end

    :ok
  end
end
