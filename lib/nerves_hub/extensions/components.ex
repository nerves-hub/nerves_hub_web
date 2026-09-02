defmodule NervesHub.Extensions.Components do
  @moduledoc """
  Lets a device report its hardware topology and take requests against it.

  On attach the platform asks once, and the device answers with everything it
  is: assemblies of components and networks of peers, each naming the health
  metrics and metadata that belong to it, plus the actions and modes it
  exposes. See `NervesHub.Devices.Components` for what is kept and why.

  There is no interval. A topology is long-lived by construction, so polling
  for it would be noise. A device whose topology has moved (a peer joined its
  Z-Wave network, a board was hot-plugged) pushes `report` again without being
  asked.

  Action and mode requests do not originate here — they are explicit
  operator-triggered messages sent through
  `NervesHub.Devices.Components.request_action/4` and
  `request_mode_change/5`, audited and recorded at the source. This module
  relays the device's results to whoever is watching the device page.
  """

  @behaviour NervesHub.Extensions

  alias NervesHub.Devices.Components
  alias NervesHub.Extensions.PubSub

  require Logger

  @impl NervesHub.Extensions
  def description() do
    """
    Reporting of the device's hardware topology — assemblies of components and
    networks of peers — with operator-invokable actions and modes.
    """
  end

  @impl NervesHub.Extensions
  def enabled?(), do: true

  @impl NervesHub.Extensions
  def attach(state) do
    {state, [{:tick, :request}]}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_in("report", payload, state) do
    device_id = state.device_info.device_id

    case Components.update_topology(device_id, payload) do
      {:ok, _component_topology} ->
        :ok

      {:error, reason} ->
        # A device on an older or simply wrong version of the client shouldn't
        # take its own connection down over this, so log it and carry on.
        Logger.warning(
          "[Components] could not store topology from device #{device_id}: " <>
            inspect(reason, limit: 5)
        )
    end

    {state, []}
  end

  def handle_in("action:result", payload, state) do
    {state, effects} = relay_result(state, "components:action_result", payload)
    {state, effects ++ refresh_reports(state)}
  end

  def handle_in("mode:result", payload, state) do
    {state, effects} = relay_result(state, "components:mode_result", payload)
    {state, effects ++ refresh_reports(state)}
  end

  def handle_in(event, payload, state) do
    Logger.warning(
      "[Components] device #{state.device_info.device_id} sent an unknown event " <>
        "#{inspect(event)}: #{inspect(payload, limit: 5)}"
    )

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_info(:request, state) do
    {state, [{:push, "components:request", %{}}]}
  end

  # Results only matter to a page somebody has open right now, so they are
  # relayed, not stored. The payload is device-supplied: it is bounded here and
  # rendered as text there, never interpreted.
  defp relay_result(state, event, payload) when is_map(payload) do
    :ok = PubSub.broadcast_report(state.device_info.device_id, event, bounded_result(payload))

    {state, []}
  end

  defp relay_result(state, _event, _payload), do: {state, []}

  @result_keys ~w(ref component action mode value status output)

  defp bounded_result(payload) do
    for {key, value} <- Map.take(payload, @result_keys), is_binary(value), into: %{} do
      {key, String.slice(value, 0, 8192)}
    end
  end

  # An action or mode change usually moves the very things the component
  # boxes show, and the next scheduled report could be minutes out. Ask for
  # fresh ones now: numbers travel through the metrics extension, and the
  # metadata that drives mode dropdowns still travels through health — a
  # device may run either or both.
  defp refresh_reports(state) do
    allowed = state.device_info.allowed_extensions || []

    for {extension, event} <- [metrics: "metrics:check", health: "health:check"],
        extension in allowed do
      {:push, event, %{}}
    end
  end
end
