defmodule NervesHub.ScriptRunners.ScriptRunnerDevice do
  @moduledoc """
  What one device did with a run's script.

  Every device the run targeted gets a row up front, so the target set is a
  matter of record even for devices nothing was sent to — `:offline` and
  `:unsupported` are outcomes, not failures to record one.
  """

  use Ecto.Schema

  alias NervesHub.Devices.Device
  alias NervesHub.ScriptRunners.ScriptRunner

  @type t :: %__MODULE__{}

  @typedoc """
  Where one device got to:

    * `:pending` — not yet dispatched
    * `:running` — the script is on its way, or being run
    * `:completed` — the device answered, and `output` holds what it said
    * `:failed` — the attempt errored
    * `:timed_out` — nothing came back inside the run's per-script timeout
    * `:offline` — the device was not connected when its turn came, so nothing
      was sent
    * `:unsupported` — the device's client is too old to run scripts

  A device is only ever `:running` while a job holds it. If the node running that
  job dies, the row is released back to `:pending` and another node picks it up —
  see `NervesHub.ScriptRunners.release_stale_devices/2`.
  """
  @type status ::
          :pending
          | :running
          | :completed
          | :failed
          | :timed_out
          | :offline
          | :unsupported

  @statuses [
    :pending,
    :running,
    :completed,
    :failed,
    :timed_out,
    :offline,
    :unsupported
  ]

  @terminal_statuses [:completed, :failed, :timed_out, :offline, :unsupported]

  schema "script_runner_devices" do
    belongs_to(:script_runner, ScriptRunner)
    belongs_to(:device, Device)

    field(:status, Ecto.Enum, values: @statuses, default: :pending)
    field(:output, :string)

    field(:started_at, :utc_datetime_usec)
    field(:finished_at, :utc_datetime_usec)

    timestamps()
  end

  @doc """
  Every status a device row can end on.
  """
  @spec terminal_statuses() :: [status(), ...]
  def terminal_statuses(), do: @terminal_statuses

  @doc """
  Every status a device row can hold.
  """
  @spec statuses() :: [status(), ...]
  def statuses(), do: @statuses
end
