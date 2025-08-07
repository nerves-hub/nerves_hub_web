defmodule NervesHub.Tracker do
  @doc """
  Tell internal listeners that the device is online, via a connection change
  """

  alias NervesHub.Devices.Device
  alias NervesHub.Repo
  alias Phoenix.Channel.Server, as: ChannelServer

  def heartbeat(%Device{} = device) do
    topic = "device:#{device.identifier}:internal"
    _ = ChannelServer.broadcast(NervesHub.PubSub, topic, "connection:heartbeat", %{})

    :ok
  end

  def connecting(%Device{} = device) do
    publish(device.identifier, "connecting")
  end

  def online(%{} = device) do
    online(device.identifier)
  end

  def online(identifier) when is_binary(identifier) do
    publish(identifier, "online")
  end

  def confirm_online(%Device{identifier: identifier}) do
    topic = "device:#{identifier}:internal"
    params = %{device_id: identifier, status: "online"}
    _ = ChannelServer.broadcast(NervesHub.PubSub, topic, "connection:status", params)

    :ok
  end

  @doc """
  Tell internal listeners that the device is offline, via a connection change
  """
  def offline(%Device{identifier: identifier}) when is_binary(identifier) do
    publish(identifier, "offline")
  end

  defp publish(identifier, status) do
    topic = "device:#{identifier}:internal"
    params = %{device_id: identifier, status: status}
    _ = ChannelServer.broadcast(NervesHub.PubSub, topic, "connection:change", params)

    :ok
  end

  @doc """
  String version of `online?/1`
  """
  def connection_status(device) do
    if online?(device) do
      "online"
    else
      "offline"
    end
  end

  @doc """
  Check if a device is currently online

  Returns `true` if device's latest connections has a status of `:connected`,
  otherwise `false`.
  """
  def online?(%{latest_connection: %Ecto.Association.NotLoaded{}} = device),
    do: online?(Repo.preload(device, :latest_connection))

  def online?(%{latest_connection: %{status: :connected}}), do: true
  def online?(_), do: false

  @doc """
  Check if a device's console channel is available.

  Times out if console is unavailable.
  """
  @spec console_active?(Device.t() | non_neg_integer()) :: boolean()
  def console_active?(%Device{id: id}) do
    console_active?(id)
  end

  def console_active?(device_id) do
    topic = "device:console:#{device_id}"
    _ = Phoenix.PubSub.broadcast(NervesHub.PubSub, topic, {:active?, self()})

    receive do
      :active ->
        true
    after
      500 ->
        false
    end
  end
end
