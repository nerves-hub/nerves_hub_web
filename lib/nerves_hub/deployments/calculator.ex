defmodule NervesHub.Deployments.Calculator do
  use GenServer

  import Ecto.Query

  require Logger

  alias NervesHub.Deployments
  alias NervesHub.Deployments.InflightDeploymentCheck
  alias NervesHub.Devices.Device
  alias NervesHub.Repo
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  def process_next_device(deployment) do
    result =
      Repo.transaction(fn ->
        inflight_check =
          InflightDeploymentCheck
          |> where([idc], idc.deployment_id == ^deployment.id)
          |> lock("FOR UPDATE SKIP LOCKED")
          |> limit(1)
          |> Repo.one()

        if !is_nil(inflight_check) do
          device = Repo.get!(Device, inflight_check.device_id)

          # Something else updated the deployment and this is now invalid
          if !is_nil(device.deployment_id) && device.deployment_id != deployment.id do
            Repo.delete!(inflight_check)

            :ignored
          else
            if deployment.is_active &&
                 !is_nil(device.connection_last_seen_at) &&
                 device.product_id == deployment.product_id &&
                 device.firmware_metadata.platform == deployment.firmware.platform &&
                 device.firmware_metadata.architecture == deployment.firmware.architecture &&
                 Enum.all?(deployment.conditions["tags"], &Enum.member?(device.tags, &1)) &&
                 Deployments.version_match?(device, deployment) do
              device
              |> Ecto.Changeset.change(%{deployment_id: deployment.id})
              |> Repo.update!()
            else
              device
              |> Ecto.Changeset.change(%{deployment_id: nil})
              |> Repo.update!()
            end

            Repo.delete!(inflight_check)

            device
          end
        else
          :none_found
        end
      end)

    case result do
      {:ok, :none_found} ->
        :none_found

      {:ok, :ignored} ->
        :ok

      {:ok, device} ->
        Phoenix.PubSub.broadcast(
          NervesHub.PubSub,
          "device:#{device.id}",
          %Phoenix.Socket.Broadcast{event: "devices/updated"}
        )

        :ok
    end
  end

  def start_link(deployment) do
    GenServer.start_link(__MODULE__, deployment)
  end

  def init(deployment) do
    {:ok, deployment, {:continue, :boot}}
  end

  def handle_continue(:boot, deployment) do
    send(self(), :process_next_device)

    PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment.id}")

    deployment = Repo.preload(deployment, [:firmware])

    state = %{
      deployment: deployment,
      process_timer_ref: nil
    }

    {:noreply, state}
  end

  def handle_info(:process_next_device, state) do
    Logger.debug("[InflightDeploymentCheck] checking next device")

    case process_next_device(state.deployment) do
      :ok ->
        send(self(), :process_next_device)

        {:noreply, %{state | process_timer_ref: nil}}

      :none_found ->
        timer_ref = Process.send_after(self(), :process_next_device, not_found_retry_interval())

        {:noreply, %{state | process_timer_ref: timer_ref}}
    end
  end

  def handle_info(%Broadcast{event: "deployments/update"}, state) do
    deployment =
      state.deployment
      |> Repo.reload()
      |> Repo.preload([:firmware], force: true)

    Logger.info("[InflightDeploymentCheck] reloaded deployment")

    if state.process_timer_ref do
      Process.cancel_timer(state.process_timer_ref)
    end

    send(self(), :process_next_device)

    state = %{state | deployment: deployment, process_timer_ref: nil}

    {:noreply, state}
  end

  # Catch all for unknown broadcasts on a deployment
  def handle_info(%Broadcast{topic: "deployment:" <> _}, deployment), do: {:noreply, deployment}

  defp not_found_retry_interval() do
    Application.get_env(:nerves_hub, :deployment_calculator_interval_seconds)
    |> :timer.seconds()
  end
end
