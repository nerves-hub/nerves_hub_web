defmodule NervesHubWeb.DeviceChannelTest do
  use NervesHubWeb.ChannelCase

  # direct channel tests need to be reconsidered

  alias NervesHubWeb.DeviceChannel

  @valid_serial "valid serial"

  # setup do
  #   {:ok, _, socket} =
  #     socket("user_id", %{serial: @valid_serial}, websocket: true)
  #     |> subscribe_and_join(DeviceChannel, "device:#{@valid_serial}")
  #
  #   {:ok, socket: socket}
  # end

  test "device_cannot_join_with_improper_id" do
    socket =
      socket(nil, "socket", %{
        serial: @valid_serial,
        websocket: %{extra_params: %{x_headers: "foo"}}
      })

    # assert {:error, socket} = subscribe_and_join(socket, DeviceChannel, "device:#{@valid_serial}")
  end
end
