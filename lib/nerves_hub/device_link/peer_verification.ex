defmodule NervesHub.DeviceLink.PeerVerification do
  @moduledoc """
  The `:ssl` verify_fun used while a device's certificate chain is validated.

  Runs inside the TLS handshake, in whatever process is terminating TLS — which
  may have no database. So it decides nothing itself: it asks
  `NervesHub.DeviceLink` and reports the answer back to `:ssl`.

  Two of the four events are answered here. Path validation reports progress as
  well as asking questions, and `:valid` and `{:extension, _}` are progress:
  they always get the same answer. Answering them locally saves a round trip per
  certificate in the chain, and `NervesHub.SSL.decide/2` answers them
  identically — there is a test that says so, because two copies of a decision
  is exactly how they come apart.

  Anything else — including the platform being unreachable — refuses the
  connection. A device that cannot be authenticated should not be admitted, and
  unlike a device that is already connected, refusing costs only a retry.
  """

  alias NervesHub.DeviceLink.Client

  @typedoc """
  What path validation is reporting about one certificate in the chain.

  Defined here rather than referenced from the platform, because this module is
  copied wherever device connections are terminated and must not depend on code
  that only exists alongside the database.
  """
  @type event() :: :valid | :valid_peer | {:bad_cert, term()} | {:extension, term()}

  @typedoc "Why a certificate was refused."
  @type reason() :: term()

  @doc """
  Answer `:ssl` about one certificate in the chain.

  The verify_fun state is threaded through untouched; it is not part of the
  decision and so never leaves this node.
  """
  @spec verify_fun(:public_key.combined_cert() | tuple(), event(), state) ::
          {:valid, state} | {:fail, reason()}
        when state: any()
  def verify_fun(_otp_cert, :valid, state), do: {:valid, state}
  def verify_fun(_otp_cert, {:extension, _}, state), do: {:valid, state}

  def verify_fun(otp_cert, event, state) do
    # DER rather than the decoded record: it is a binary, so it does not depend
    # on two nodes agreeing about the shape of an OTP certificate.
    der = :public_key.pkix_encode(:OTPCertificate, otp_cert, :otp)

    case Client.verify_peer(der, event) do
      :valid -> {:valid, state}
      {:fail, reason} -> {:fail, reason}
    end
  catch
    kind, reason ->
      # Failing closed. This runs during a handshake, so there is nobody to
      # retry on behalf of and nothing to degrade to -- the device will try
      # again, and by then the platform may be reachable.
      :telemetry.execute([:nerves_hub, :ssl, :unavailable], %{count: 1}, %{
        kind: kind,
        reason: reason
      })

      {:fail, :platform_unavailable}
  end
end
