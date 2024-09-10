defmodule NervesHub.Workers.FirmwareDeltaBuilder do
  use Oban.Worker,
    max_attempts: 5,
    queue: :firmware_delta_builder,
    unique: [
      period: 60 * 10,
      states: [:available, :scheduled, :executing]
    ]

  require Logger

  alias NervesHub.{Deployments, Firmwares}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => source_id, "target_id" => target_id}}) do
    source = Firmwares.get_firmware!(source_id)
    target = Firmwares.get_firmware!(target_id)

    {:ok, _firmware_delta} = maybe_create_firmware_delta(source, target)

    Enum.each(Deployments.get_deployments_by_firmware(target_id), fn deployment ->
      Deployments.broadcast(deployment, "deployments/update")
    end)

    :ok
  end

  def start(source_id, target_id) do
    {:ok, _job} =
      %{source_id: source_id, target_id: target_id}
      |> __MODULE__.new()
      |> Oban.insert()

    :ok
  end

  defp maybe_create_firmware_delta(source, target) do
    case Firmwares.get_firmware_delta_by_source_and_target(source, target) do
      {:ok, firmware_delta} ->
        {:ok, firmware_delta}

      {:error, :not_found} ->
        {:ok, _firmware_delta} = Firmwares.create_firmware_delta(source, target)
    end
  end
end
