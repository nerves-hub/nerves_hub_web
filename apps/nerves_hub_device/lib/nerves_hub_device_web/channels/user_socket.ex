defmodule NervesHubDeviceWeb.UserSocket do
  use Phoenix.Socket
  alias NervesHubCore.{Certificate, Devices}


  @websocket_auth_methods Application.get_env(:nerves_hub_device, :websocket_auth_methods)

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

  if Enum.member?(@websocket_auth_methods, :header) do
    @serial_header Application.get_env(:nerves_hub_device, :device_serial_header)

    def connect(%{x_headers: %{@serial_header => serial}}, socket) do
      build_socket(socket, serial)
    end
  end

  if Enum.member?(@websocket_auth_methods, :ssl) do
    def connect(%{ssl_cert: ssl_cert}, socket) do
      case Certificate.get_common_name(ssl_cert) do
        {:ok, serial} -> build_socket(socket, serial)
        error -> error
      end
    end
  end

  def connect(_params, _socket) do
    :error
  end

  defp build_socket(socket, serial) do
    with {:ok, device} <- Devices.get_device_by_identifier(serial) do
      new_socket =
        socket
        |> assign(:device, device)
        |> assign(:tenant, device.tenant)

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
  def id(_socket), do: nil
end
