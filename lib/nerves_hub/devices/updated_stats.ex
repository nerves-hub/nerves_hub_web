defmodule NervesHub.Devices.UpdateStats do
  @moduledoc """
  Module for logging and queryingdevice update statistics.
  """

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Devices.UpdateStat

  @doc """
  Log an update statistic for a device.
  """
  @spec log_stat(
          Device.t(),
          DeploymentGroup.t(),
          update_bytes :: non_neg_integer(),
          saved_bytes :: integer()
        ) :: :ok | {:error, Ecto.Changeset.t()}
  def log_stat(
        %Device{} = device,
        %DeploymentGroup{} = deployment_group,
        update_bytes,
        saved_bytes \\ 0
      ) do
    changeset =
      UpdateStat.create_changeset(device, deployment_group, %{
        update_bytes: update_bytes,
        saved_bytes: saved_bytes
      })

    case Ecto.Changeset.apply_action(changeset, :create) do
      {:ok, _stat} ->
        _ = AnalyticsRepo.insert_all(UpdateStat, [changeset.changes], settings: [async_insert: 1])

        _ =
          Phoenix.Channel.Server.broadcast(
            NervesHub.PubSub,
            "deployment:#{deployment_group.id}:internal",
            "stat:logged",
            {:update_stat, update_bytes, saved_bytes}
          )

        :ok

      error ->
        error
    end
  end
end
