defmodule NervesHub.Utils.SSLLoggingFilter do
  @moduledoc """
  The Erlang SSL application will log issues or failures related to verification of certificates.

  This filter is designed to ignore certain SSL handshake errors that are not relevant to the application's operation.

  eg. TLS :server: In state :certify at ssl_handshake.erl:2201 generated SERVER ALERT: Fatal - Handshake Failure - :unknown_ca
  """

  def filter(log_event, _opts) do
    case log_event do
      %{msg: {:report, %{alert: {:alert, _, _, %{file: ~c"ssl_handshake.erl"}, _, :unknown_ca}}}} ->
        :stop

      _ ->
        :ignore
    end
  end
end
