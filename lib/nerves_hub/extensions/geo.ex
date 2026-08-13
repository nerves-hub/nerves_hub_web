defmodule NervesHub.Extensions.Geo do
  @behaviour NervesHub.Extensions

  alias NervesHub.Devices.Connections
  alias Phoenix.Channel.Server, as: ChannelServer

  @impl NervesHub.Extensions
  def description() do
    """
    Reporting of GeoIP information or custom geo-location information sources
    you've set up for your device.
    """
  end

  @impl NervesHub.Extensions
  def enabled?() do
    true
  end

  @impl NervesHub.Extensions
  def attach(state) do
    # The initial request is unconditional; only the repeat is configurable.
    effects =
      case geo_interval_minutes() do
        interval when interval > 0 ->
          [{:tick, :location_request}, {:start_timer, :location_request, :timer.minutes(interval)}]

        _ ->
          [{:tick, :location_request}]
      end

    {state, effects}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    {state, [{:cancel_timer, :location_request}]}
  end

  @impl NervesHub.Extensions
  def handle_in("location:update", location, state) do
    device_info = state.device_info

    :ok = Connections.merge_update_metadata(device_info.connection_ref, %{location: location})

    _ =
      ChannelServer.broadcast(
        NervesHub.PubSub,
        "internal:device:#{device_info.device_id}",
        "location:updated",
        location
      )

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_info(:location_request, state) do
    {state, [{:push, "geo:location:request", %{}}]}
  end

  defp geo_interval_minutes() do
    extension_config = Application.get_env(:nerves_hub, :extension_config)
    get_in(extension_config, [:geo, :interval_minutes]) || 0
  end
end
