defmodule NervesHub.Tracker do
  @doc """
  Tell internal listeners that the device is online, via a connection change
  """
  def online(%{} = device) do
    online(device.identifier)
  end

  def online(identifier) when is_binary(identifier) do
    publish(identifier, "online")
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
    message = %Phoenix.Socket.Broadcast{
      event: "connection_change",
      payload: %{
        device_id: identifier,
        status: status
      }
    }

    Phoenix.PubSub.broadcast(NervesHub.PubSub, "device:#{identifier}:internal", message)

    :ok
  end

  @doc """
  String version of `online?/1`
  """
  def status(device) do
    if online?(device) do
      "online"
    else
      "offline"
    end
  end

  @doc """
  Check if a device is currently online

  Returns `false` immediately but sends a message to the device's channel asking if it's
  online. If the device is online, it will send a connection state change of online.
  """
  def online?(device) do
    Phoenix.PubSub.broadcast(NervesHub.PubSub, "device:#{device.id}", :online?)
    false
  end

  @doc """
  Check if a device is currently online

  If the device is not online this function will wait for a timeout before returning false
  """
  def sync_online?(device) do
    Phoenix.PubSub.broadcast(NervesHub.PubSub, "device:#{device.id}", {:online?, self()})

    receive do
      :online ->
        true
    after
      500 ->
        false
    end
  end
end
