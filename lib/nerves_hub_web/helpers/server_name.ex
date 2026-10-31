defmodule NervesHubWeb.Helpers.ServerName do
  @moduledoc """
  The hostname a device asked for in its TLS handshake, for its socket to check.

  A socket is only given what `connect_info` can ask for, and the handshake isn't
  part of that. So the device endpoint records the name before it dispatches the
  request and the socket reads it back, which works because Bandit runs both in the
  connection's process.

  This is the SNI and not the Host header, because it's the name that chose the
  certificate the device was served. `:ssl` reports the name from this connection's
  own handshake, even when it resumes a session that began under another name.

  Nothing is recorded for a device that sent no name, or a connection with TLS
  terminated ahead of us, as on the web endpoint.
  """

  @key {__MODULE__, :server_name}

  @spec record(Plug.Conn.t()) :: :ok
  def record(conn) do
    _ = Process.put(@key, server_name(conn))
    :ok
  end

  @spec recorded() :: String.t() | nil
  def recorded(), do: Process.get(@key)

  defp server_name(conn) do
    case Plug.Conn.get_ssl_data(conn) do
      nil -> nil
      ssl_data -> ssl_data |> Keyword.get(:sni_hostname) |> to_name()
    end
  rescue
    # The device has hung up, so there's no connection left to check.
    Bandit.TransportError -> nil
  end

  defp to_name(nil), do: nil
  defp to_name(hostname), do: to_string(hostname)
end
