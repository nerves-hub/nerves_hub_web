defmodule NervesHub.DeviceSSLTransport do
  @moduledoc """
  SSL transport for device certificate authentication

  This transport exists to rate limit incoming SSL connections _before_ any
  ssl work has started. This let's us shed incoming devices before we waste
  a lot of resources on denying them midway through the SSL connection in
  the `NervesHub.SSL.verify_fun/3`

  See `handshake/1` for the main change. All other function are delegated back to
  `ThousandIsland.Transports.SSL`
  """

  @behaviour ThousandIsland.Transport

  alias ThousandIsland.Transports.SSL

  @impl ThousandIsland.Transport
  defdelegate listen(port, user_options), to: SSL

  @impl ThousandIsland.Transport
  defdelegate accept(listener_socket), to: SSL

  @impl ThousandIsland.Transport
  def handshake(socket) do
    if NervesHub.RateLimit.increment() do
      :telemetry.execute([:nerves_hub, :rate_limit, :accepted], %{count: 1})

      SSL.handshake(socket)
    else
      :telemetry.execute([:nerves_hub, :rate_limit, :rejected], %{count: 1})

      {:error, :closed}
    end
  end

  @impl ThousandIsland.Transport
  defdelegate upgrade(socket, opts), to: SSL

  @impl ThousandIsland.Transport
  defdelegate controlling_process(socket, pid), to: SSL

  @impl ThousandIsland.Transport
  defdelegate recv(socket, length, timeout), to: SSL

  @impl ThousandIsland.Transport
  defdelegate send(socket, data), to: SSL

  @impl ThousandIsland.Transport
  defdelegate sendfile(socket, filename, offset, length), to: SSL

  @impl ThousandIsland.Transport
  defdelegate getopts(socket, options), to: SSL

  @impl ThousandIsland.Transport
  defdelegate setopts(socket, options), to: SSL

  @impl ThousandIsland.Transport
  defdelegate shutdown(socket, way), to: SSL

  @impl ThousandIsland.Transport
  defdelegate close(socket), to: SSL

  @impl ThousandIsland.Transport
  defdelegate sockname(socket), to: SSL

  @impl ThousandIsland.Transport
  defdelegate peername(socket), to: SSL

  @impl ThousandIsland.Transport
  defdelegate peercert(socket), to: SSL

  @impl ThousandIsland.Transport
  defdelegate secure?(), to: SSL

  @impl ThousandIsland.Transport
  defdelegate getstat(socket), to: SSL

  @impl ThousandIsland.Transport
  defdelegate negotiated_protocol(socket), to: SSL

  @impl ThousandIsland.Transport
  defdelegate connection_information(socket), to: SSL
end
