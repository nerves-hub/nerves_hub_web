defmodule NervesHub.Workers.ExpireInflightUpdates do
  @moduledoc """
  Expire inflight updates every 5 minutes

  Expiration is set from the deployment when the inflight update is recorded.
  """

  use Oban.Worker,
    max_attempts: 1,
    queue: :truncate

  require Logger

  alias NervesHub.Devices

  @impl true
  def perform(_) do
    {count, _} = Devices.delete_expired_inflight_updates()

    if count > 0 && prod?() do
      Logger.info("Expired #{count} inflight updates")
    end

    :ok
  end

  def prod?() do
    Application.get_env(:nerves_hub, :deploy_env) == "prod"
  end
end
