defmodule BeamwareClient do
  alias BeamwareClient.{Socket, DeviceChannel}

  def connect do
    {:ok, _socket} = Socket.start_link()

    {:ok, _channel} =
      DeviceChannel.start_link(socket: BeamwareClient.Socket, topic: "device:lobby")

    DeviceChannel.join()
  end
end
