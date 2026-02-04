defmodule NervesHub.Support.EctoTelemetryHandler do
  @moduledoc """
  A module for attaching to Ecto telemetry events during tests. When integration
  testing, such as in NervesHubWeb.WebsocketTest, it's very difficult to leverage
  Mimic. Processes that are in charge of doing the work are abstracted away
  from any deterministic way to access them.

  Usually, we just want to make sure something is or isn't updated in the database.
  Ecto allows us to easily consume telemetry events for queries, so we can track
  when certain queries are or aren't made.

  Curretly only supports tracking UPDATE queries, but can be extended as needed.

  Usage:

      :ok = EctoTelemetryHandler.start_and_attach()
      ...
      assert EctoTelemetryHandler.has_queried?(:update, schema, "some_field")
      ...
      EctoTelemetryHandler.detach()
  """
  use Agent

  def start_and_attach() do
    {:ok, _pid} = Agent.start_link(fn -> [] end, name: __MODULE__)

    :telemetry.attach(
      __MODULE__,
      [:nerves_hub, :repo, :query],
      &handle_event/4,
      %{}
    )
  end

  def detach(), do: :telemetry.detach(__MODULE__)

  # Check if an UPDATE query has been made for a given schema and field
  @spec has_queried?(atom(), Ecto.Schema.t(), String.t()) :: boolean()
  def has_queried?(:update, schema, field) do
    events = Agent.get(__MODULE__, & &1)

    Enum.any?(events, fn event ->
      {:ok, result} = event.result

      result.command == :update and
        event.source == schema.__meta__.source and
        Enum.member?(event.params, schema.id) and
        String.contains?(event.query, "SET \"#{field}\"")
    end)
  end

  def handle_event([:nerves_hub, :repo, :query], _measurements, metadata, _config) do
    Agent.update(__MODULE__, fn state -> state ++ [metadata] end)
  end
end
