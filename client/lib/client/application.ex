defmodule BeamwareClient.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      {BeamwareClient.Socket, []},
      {BeamwareClient.DeviceChannel, [socket: BeamwareClient.Socket, topic: "device:lobby"]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BeamwareClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
