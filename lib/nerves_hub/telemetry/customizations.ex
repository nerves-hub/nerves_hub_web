defmodule NervesHub.Telemetry.Customizations do
  alias NervesHub.Telemetry.RequestPath
  alias OpenTelemetry.SemConv.URLAttributes
  alias OpenTelemetry.Tracer

  def setup() do
    :ok =
      :telemetry.attach_many(
        {__MODULE__, :bandit_customizations},
        [
          [:bandit, :request, :stop]
        ],
        &__MODULE__.handle_request/4,
        nil
      )

    :telemetry.attach(
      {__MODULE__, :request_path},
      [:phoenix, :router_dispatch, :start],
      &__MODULE__.handle_router_dispatch/4,
      nil
    )
  end

  # Bandit puts the path on the request's span as soon as the request arrives,
  # before anything knows which part of it is a token. The router knows when it
  # dispatches, and the span is still open then, even if the action goes on to
  # raise.
  def handle_router_dispatch([:phoenix, :router_dispatch, :start], _measurements, %{conn: conn}, _config) do
    path = RequestPath.recordable(conn)

    if path != conn.request_path do
      Tracer.set_attribute(URLAttributes.url_path(), path)
    end

    :ok
  end

  def handle_request([:bandit, :request, :stop], _measurements, %{conn: conn}, _config) do
    if conn.request_path =~ ~r/\/websocket$/ do
      Tracer.update_name("WEBSOCKET #{conn.request_path}")
    end

    :ok
  end

  def handle_request([:bandit, :request, :stop], _measurements, _metadata, _config) do
    # Handle cases where conn is not present (e.g., timeouts, errors)
    :ok
  end
end
