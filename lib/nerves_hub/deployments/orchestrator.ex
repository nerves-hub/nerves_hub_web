defmodule NervesHub.Deployments.Orchestrator do
  @moduledoc """
  Orchestration process to handle passing out updates to devices

  When a deployment is updated, the orchestraor will tell every
  device local to its node that there is a new update. This will
  hook will allow the orchestrator to start slowly handing out
  updates instead of blasting every device at once.
  """

  use GenServer

  require Logger

  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Repo
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  def start_link(deployment) do
    GenServer.start_link(__MODULE__, deployment, name: name(deployment))
  end

  def name(deployment_id) when is_integer(deployment_id) do
    {:via, Registry, {NervesHub.Deployments, deployment_id}}
  end

  def name(deployment), do: name(deployment.id)

  @doc """
  Send updates to connected devices for this deployment
  """
  def send_update(deployment) do
    match_return = %{device_id: {:element, 1, :"$_"}, pid: {:element, 1, {:element, 2, :"$_"}}}

    devices =
      Registry.select(NervesHub.Devices, [
        {{:_, :_, %{deployment_id: deployment.id}}, [], [match_return]}
      ])

    Enum.each(devices, fn %{device_id: device_id, pid: pid} ->
      device = %Device{id: device_id}

      case Devices.told_to_update(device, deployment) do
        {:ok, inflight_update} ->
          send(pid, {"deployments/update", inflight_update})

        {:error, _changeset} ->
          Logger.error("Could not update device #{device_id}")
      end
    end)
  end

  def init(deployment) do
    {:ok, deployment, {:continue, :boot}}
  end

  def handle_continue(:boot, deployment) do
    PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment.id}")

    {:noreply, deployment}
  end

  def handle_info(%Broadcast{event: "deployments/update"}, deployment) do
    deployment =
      deployment
      |> Repo.reload()
      |> Repo.preload([:firmware])

    send_update(deployment)

    {:noreply, deployment}
  end

  # Catch all for unknown broadcasts on a deployment
  def handle_info(%Broadcast{topic: "deployment:" <> _}, deployment), do: {:noreply, deployment}
end
