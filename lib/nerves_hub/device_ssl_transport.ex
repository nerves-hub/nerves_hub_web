defmodule NervesHub.DeviceSSLTransport do
  @moduledoc """
  SSL transport for device certificate authentication

  This transport exists to rate limit incoming SSL connections _before_ any
  ssl work has started. This let's us shed incoming devices before we waste
  a lot of resources on denying them midway through the SSL connection in
  the `NervesHub.SSL.verify_fun/3`

  See `handshake/1` for the main change. All other function are delegated back to
  `:ranch_ssl`
  """

  @behaviour :ranch_transport

  @impl :ranch_transport
  defdelegate name(), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate secure(), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate messages(), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate listen(transport_opts), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate accept(listener_socket, timeout), to: :ranch_ssl

  @impl :ranch_transport
  def handshake(socket, opts \\ [], timeout) do
    if NervesHub.RateLimit.increment() do
      :telemetry.execute([:nerves_hub, :rate_limit, :accepted], %{count: 1})

      :ranch_ssl.handshake(socket, opts, timeout)
    else
      :telemetry.execute([:nerves_hub, :rate_limit, :rejected], %{count: 1})

      {:error, :closed}
    end
  end

  @impl :ranch_transport
  defdelegate connect(string, port, opts), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate connect(string, port, opts, timeout), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate recv(socket, length, timeout), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate recv_proxy_header(socket, timeout), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate send(socket, iodata), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate sendfile(socket, file), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate sendfile(socket, file, offset, bytes), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate sendfile(socket, file, offset, bytes, opts), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate setopts(socket, opts), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate getopts(socket, opt_list), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate getstat(socket), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate getstat(socket, stat_list), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate controlling_process(socket, pid), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate peername(socket), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate sockname(socket), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate shutdown(socket, how), to: :ranch_ssl

  @impl :ranch_transport
  defdelegate close(socket), to: :ranch_ssl

  ##
  # These will be required in ranch > 1.8

  # @impl :ranch_transport
  # defdelegate handshake_continue(socket, timeout), to: :ranch_ssl
  # @impl :ranch_transport
  # defdelegate handshake_continue(socket, opts, timeout), to: :ranch_ssl
  # @impl :ranch_transport
  # defdelegate handshake_cancel(socket), to: :ranch_ssl
  # @impl :ranch_transport
  # defdelegate cleanup(transport_opts), to: :ranch_ssl
end
