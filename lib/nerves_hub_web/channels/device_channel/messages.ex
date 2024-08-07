defmodule NervesHubWeb.DeviceChannel.Messages do
  @moduledoc false
  alias NervesHub.Devices.Device

  require Logger
  @type alarm_id() :: String.t()
  @type alarm_description() :: String.t()

  @type health_check_report() :: %{
          timestamp: DateTime.t(),
          metadata: %{String.t() => String.t()},
          alarms: %{alarm_id() => alarm_description()},
          metrics: %{String.t() => number()},
          checks: %{String.t() => %{pass: boolean(), note: String.t()}}
        }

  @type scripts_run() :: %{
          ref: String.t(),
          output: String.t(),
          return: String.t()
        }

  @type fwup_progress() :: %{
          percent: integer()
        }

  @type location() :: term()

  @type connection_types() :: %{types: list(atom())}

  @type status_update() :: map()

  @type check_update_available() :: map()

  # We parse out messages explicitly to let the compiler help with types and
  # to keep track of what we have coming in and out of the system
  # They are not structs to reduce the proliferation of modules for what is mostly
  # an inbetween layer
  # If the role of these definitions grows to much it may make sense to turn them into
  # structs.
  @spec parse(event :: String.t(), params :: map()) ::
          {:fwup_progress, fwup_progress()}
          | {:location_update, location()}
          | {:connection_types, connection_types()}
          | {:status_update, status_update()}
          | {:check_update_available, check_update_available()}
          | {:health_check_report, health_check_report()}
          | {:scripts_run, scripts_run()}
          | {:rebooting, map()}
          | {:unknown, map()}
  def parse(event, params)

  def parse("fwup_progress", %{"value" => percent}) do
    {:fwup_progress, %{percent: percent}}
  end

  def parse("location:update", location) do
    {:location_update, location}
  end

  @valid_types Device.connection_types()
  def parse("connection_types", %{"values" => types}) do
    types =
      types
      |> Enum.map(fn type ->
        try do
          String.to_existing_atom(type)
        rescue
          _ -> nil
        end
      end)
      |> Enum.filter(fn type ->
        if type in @valid_types do
          true
        else
          Logger.warning("Received invalid type for connection_types: #{inspect(type)}")
          false
        end
      end)

    {:connection_types, %{types: types}}
  end

  def parse("status_update", %{"status" => _status}) do
    {:status_update, %{}}
  end

  def parse("check_update_available", _params) do
    {:check_update_available, %{}}
  end

  def parse("health_check_report", %{
        "value" => %{
          "timestamp" => iso_ts,
          "metadata" => metadata,
          "alarms" => alarms,
          "metrics" => metrics,
          "checks" => checks
        }
      }) do
    {:ok, ts, _} = DateTime.from_iso8601(iso_ts)

    status = %{
      timestamp: ts,
      metadata: metadata,
      alarms: alarms,
      metrics: metrics,
      checks: to_checks(checks)
    }

    {:health_check_report, status}
  end

  def parse("scripts/run", %{"ref" => ref, "output" => output, "return" => return}) do
    {:scripts_run, %{ref: ref, output: output, return: return}}
  end

  def parse("rebooting", _) do
    {:rebooting, %{}}
  end

  def parse(event, params) do
    Logger.warning(
      "Unmatched incoming event in device channel messages '#{event}' with #{inspect(params)}"
    )

    {:unknown, params}
  end

  defp to_checks(checks) do
    for {key, %{"pass" => pass, "note" => note}} <- checks, into: %{} do
      {key, %{pass: pass, note: note}}
    end
  end
end
