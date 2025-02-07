defmodule NervesHub.Tracker do
  @doc """
  Tell internal listeners that the device is online, via a connection change
  """

  alias NervesHub.Devices.Device
  alias NervesHub.Repo

  def online(%{} = device) do
    online(device.identifier)
  end

  def online(identifier) when is_binary(identifier) do
    publish(identifier, "online")
  end

  def confirm_online(%Device{identifier: identifier}) do
    _ =
      Phoenix.Channel.Server.broadcast(
        NervesHub.PubSub,
        "device:#{identifier}:internal",
        "connection:status",
        %{
          device_id: identifier,
          status: "online"
        }
      )

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
    _ =
      Phoenix.Channel.Server.broadcast(
        NervesHub.PubSub,
        "device:#{identifier}:internal",
        "connection:change",
        %{
          device_id: identifier,
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
  Check if a device is currently online

  If the device is not online this function will wait for a timeout before returning false
  """
  def sync_online?(device) do
    _ = Phoenix.PubSub.broadcast(NervesHub.PubSub, "device:#{device.id}", {:online?, self()})

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
  def console_active?(device) do
    _ =
      Phoenix.PubSub.broadcast(
        NervesHub.PubSub,
        "device:console:#{device.id}",
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
