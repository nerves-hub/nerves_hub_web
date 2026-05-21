defmodule NervesHub.Tracker do
  alias NervesHub.Devices.Device
  alias NervesHub.Repo
  alias Phoenix.Channel.Server, as: ChannelServer

  @doc """
  Tell internal listeners that the device is online, via a connection change
  """

  def heartbeat(%Device{} = device) do
    heartbeat(device.id)
  end

  def heartbeat(device_id) when is_integer(device_id) do
    _ =
      ChannelServer.broadcast(
        NervesHub.PubSub,
        "internal:device:#{device_id}",
        "connection:heartbeat",
        %{}
      )

    :ok
  end

  def connecting(%Device{} = device) do
    connecting(device.id)
  end

  def connecting(device_id) when is_integer(device_id) do
    publish(device_id, "connecting")
  end

  def online(%Device{} = device) do
    online(device.id)
  end

  def online(device_id) when is_integer(device_id) do
    publish(device_id, "online")
  end

  @doc """
  Tell internal listeners that the device is offline, via a connection change
  """
  def offline(%Device{} = device) do
    offline(device.id)
  end

  def offline(device_id) when is_integer(device_id) do
    publish(device_id, "offline")
  end

  defp publish(device_id, status) do
    _ =
      ChannelServer.broadcast(
        NervesHub.PubSub,
        "internal:device:#{device_id}",
        "connection:change",
        %{
          status: status
        }
      )

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
    _ =
      Phoenix.PubSub.broadcast(
        NervesHub.PubSub,
        "device:console:#{device_id}",
        {:active?, self()}
      )

    receive do
      :active ->
        true
    after
      500 ->
        false
    end
  end
end
