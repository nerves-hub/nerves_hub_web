defmodule NervesHubDeviceWeb.UserSocket do
  use Phoenix.Socket
  alias NervesHubCore.{Certificate, Devices}

  ## Channels
  # channel "room:*", NervesHubWWWWeb.RoomChannel
  channel("device:*", NervesHubDeviceWeb.DeviceChannel)

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error`.
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.

  def connect(_params, socket, %{peer_data: %{ssl_cert: ssl_cert}}) do
    case Certificate.get_serial_number(ssl_cert) do
      {:ok, serial} ->
        build_socket(socket, serial)

      error ->
        error
    end
  end

  def connect(_params, _socket, _connect_info) do
    :error
  end

  defp build_socket(socket, serial) do
    with {:ok, cert} <- Devices.get_device_certificate_by_serial(serial) do
      cert = NervesHubCore.Repo.preload(cert, device: :org)

      new_socket =
        socket
        |> assign(:certificate, cert)

      {:ok, new_socket}
    else
      _ -> :error
    end
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     NervesHubWWWWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  def id(%{assigns: %{certificate: certificate}}), do: "device:#{certificate.device.id}"
  def id(_socket), do: nil
end
