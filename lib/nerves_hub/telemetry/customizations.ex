defmodule NervesHub.Telemetry.Customizations do
  alias OpenTelemetry.Tracer
  require OpenTelemetry.Tracer

  def setup() do
    :telemetry.attach_many(
      {__MODULE__, :bandit_customizations},
      [
        [:bandit, :request, :stop]
      ],
      &__MODULE__.handle_request/4,
      nil
    )
  end

  def handle_request([:bandit, :request, :stop], _measurements, %{conn: conn}, _config) do
    if conn.status == 101 do
      Tracer.update_name("WEBSOCKET #{conn.request_path}")
    end

    :ok
  end
end
