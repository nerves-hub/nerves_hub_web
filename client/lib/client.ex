defmodule NervesHubClient do
  alias NervesHubClient.{Socket, DeviceChannel}

  def connect do
    {:ok, _socket} = Socket.start_link()

    {:ok, _channel} =
      DeviceChannel.start_link(socket: NervesHubClient.Socket, topic: "device:lobby")

    DeviceChannel.join()
  end
end
