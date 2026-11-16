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
    * `:abandoned` — the script was sent, but the job ended without recording
      what happened, so whether it ran is unknown. It is not sent again.

  A device is only ever `:running` while a job holds it. If that job ends without
  recording an outcome, the row is released back to `:pending` when the script
  was never sent, and marked `:abandoned` when it was — see
  `NervesHub.ScriptRunners.release_stale_devices/2`.
  """
  @type status :: :pending | :running | terminal_status()

  @typedoc """
  A status a device row stops on.

  Split out from `t:status/0` because the two statuses missing here, `:pending` and
  `:running`, are exactly the ones a device can still move off — which is what
  makes "finished" countable. See `terminal_statuses/0`.
  """
  @type terminal_status :: :completed | :failed | :timed_out | :offline | :unsupported | :abandoned

  @statuses [
    :pending,
    :running,
    :completed,
    :failed,
    :timed_out,
    :offline,
    :unsupported,
    :abandoned
  ]

  @terminal_statuses [:completed, :failed, :timed_out, :offline, :unsupported, :abandoned]

  schema "script_runner_devices" do
    belongs_to(:script_runner, ScriptRunner)
    belongs_to(:device, Device)

    field(:status, Ecto.Enum, values: @statuses, default: :pending)
    field(:output, :string)

    field(:started_at, :utc_datetime_usec)

    # When the script was handed to the device. See
    # `NervesHub.ScriptRunners.mark_sent/2`.
    field(:sent_at, :utc_datetime_usec)

    field(:finished_at, :utc_datetime_usec)

    # Set when `output` was cleared for outliving its retention period. See
    # `NervesHub.ScriptRunners.expire_output/2`.
    field(:output_expired_at, :utc_datetime_usec)

    timestamps()
  end

  @doc """
  Every field except `output`, for listings that show a page of rows without
  their output. Output is uncapped by row count and can be large, so it is only
  read for the one row someone opens.
  """
  @spec fields_without_output() :: [atom(), ...]
  def fields_without_output(), do: __schema__(:fields) -- [:output]

  @doc """
  Every status a device row can end on.
  """
  @spec terminal_statuses() :: [terminal_status(), ...]
  def terminal_statuses(), do: @terminal_statuses

  @doc """
  Every status a device row can hold.
  """
  @spec statuses() :: [status(), ...]
  def statuses(), do: @statuses
end
