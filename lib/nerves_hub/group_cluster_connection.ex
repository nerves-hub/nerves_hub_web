defmodule NervesHub.GroupClusterConnection do
  @moduledoc """
  Connects this node to the named "web" Group cluster on startup.

  The "web" cluster scopes membership replication for web-only pub/sub state
  (currently rate limiting) to the handful of web/all nodes, keeping that state
  off the more numerous device nodes. Device-role nodes never serve this traffic,
  so they do not connect.
  """

  use GenServer

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      restart: :permanent
    }
  end

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  @impl GenServer
  def init(_) do
    _ =
      if Application.get_env(:nerves_hub, :app) != "device" do
        :ok = Group.connect(NervesHub.Group, "web")
      end

    {:ok, nil}
  end
end
