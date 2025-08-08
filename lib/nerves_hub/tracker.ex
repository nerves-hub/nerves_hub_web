defmodule NervesHub.Tracker do
  @doc """
  Tell internal listeners that the device is online, via a connection change
  """

  alias NervesHub.Devices.Device
  alias NervesHub.Repo
  alias Phoenix.Channel.Server
  alias Phoenix.PubSub

  def online(%{} = device) do
    online(device.identifier)
  end

  def online(identifier) when is_binary(identifier) do
    publish(identifier, "online")
  end

  def confirm_online(%Device{identifier: identifier}) do
    topic = "device:#{identifier}:internal"
    params = %{device_id: identifier, status: "online"}
    _ = Server.broadcast(NervesHub.PubSub, topic, "connection:status", params)

    :ok
  end

  @doc """
  Tell internal listeners that the device is offline, via a connection change
  """
  def offline(%{} = device) do
    offline(device.identifier)
  end

  def offline(identifier) when is_binary(identifier) do
    publish(identifier, "offline")
  end

  defp publish(identifier, status) do
    topic = "device:#{identifier}:internal"
    params = %{device_id: identifier, status: status}
    _ = Server.broadcast(NervesHub.PubSub, topic, "connection:change", params)

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
  Check if a device is currently online

  If the device is not online this function will wait for a timeout before returning false
  """
  def sync_online?(device) do
    _ = PubSub.broadcast(NervesHub.PubSub, "device:#{device.id}", {:online?, self()})

    receive do
      :online ->
        true
    after
      500 ->
        false
    end
  end

  @doc """
  Check if a device's console channel is available.

  Times out if console is unavailable.
  """
  @spec console_active?(Device.t() | non_neg_integer()) :: boolean()
  def console_active?(%Device{id: id}) do
    console_active?(id)
  end

  def console_active?(device_id) do
    _ = PubSub.broadcast(NervesHub.PubSub, "device:console:#{device_id}", {:active?, self()})

    receive do
      :active ->
        true
    after
      500 ->
        false
    end
  end
end
