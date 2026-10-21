defmodule NervesHub.DeviceLink.PeerVerificationTest do
  @moduledoc """
  The verify_fun that runs inside a device's TLS handshake.

  It answers two events itself and asks the platform about the rest. Two copies
  of a decision is how decisions come apart, so the copies are compared here
  rather than assumed to match.
  """

  use ExUnit.Case, async: false

  alias NervesHub.DeviceLink.Dispatcher
  alias NervesHub.DeviceLink.PeerVerification
  alias NervesHub.Fixtures
  alias NervesHub.SSL

  setup do
    on_exit(fn -> Application.delete_env(:nerves_hub, Dispatcher) end)
  end

  defp certificate() do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "/CN=Peer Verification Test CA", template: :root_ca)

    device_key = X509.PrivateKey.new_ec(:secp256r1)

    device_key
    |> X509.PublicKey.derive()
    |> X509.Certificate.new("/CN=peer-verification-device", ca, ca_key)
  end

  describe "events answered without asking the platform" do
    setup do
      # Anything reaching the platform in these tests is a mistake, so make it loud.
      Application.put_env(:nerves_hub, Dispatcher, __MODULE__.Unreachable)
      :ok
    end

    test ":valid is progress, not a question" do
      assert {:valid, :state} = PeerVerification.verify_fun(certificate(), :valid, :state)
    end

    test "an extension is progress, not a question" do
      assert {:valid, :state} =
               PeerVerification.verify_fun(certificate(), {:extension, :whatever}, :state)
    end

    test "they answer exactly what the platform would have answered" do
      cert = certificate()

      for event <- [:valid, {:extension, :whatever}] do
        {shortcut, _state} = PeerVerification.verify_fun(cert, event, :state)

        assert shortcut == SSL.decide(cert, event),
               """
               PeerVerification answers #{inspect(event)} locally to save a round trip per
               certificate in the chain. That is only safe while it matches
               NervesHub.SSL.decide/2, and it no longer does.
               """
      end
    end

    defmodule Unreachable do
      @moduledoc false
      @behaviour Dispatcher

      @impl Dispatcher
      def call(function, _args) do
        raise "#{function} should have been answered without asking the platform"
      end
    end
  end

  describe "events the platform decides" do
    test "the certificate is sent as DER, and a decision comes back" do
      test = self()
      cert = certificate()

      stub(fn :verify_peer, [der, event] ->
        send(test, {:asked, der, event})
        :valid
      end)

      assert {:valid, :state} = PeerVerification.verify_fun(cert, :valid_peer, :state)

      assert_received {:asked, der, :valid_peer}
      assert is_binary(der), "DER travels between nodes; a decoded record depends on OTP internals"

      assert X509.Certificate.from_der!(der) == cert,
             "the certificate must survive encoding, or the platform decides about a different one"
    end

    test "a refusal is passed back to ssl with its reason" do
      stub(fn :verify_peer, _args -> {:fail, :unknown_device_certificate} end)

      assert {:fail, :unknown_device_certificate} =
               PeerVerification.verify_fun(certificate(), :valid_peer, :state)
    end

    test "a bad certificate is a question, not progress" do
      stub(fn :verify_peer, [_der, event] ->
        send(self(), {:asked, event})
        :valid
      end)

      assert {:valid, :state} =
               PeerVerification.verify_fun(certificate(), {:bad_cert, :unknown_ca}, :state)
    end
  end

  # Which event a certificate arrives as is up to :ssl, so this takes a real
  # handshake. A certificate that signed itself, sent on its own, arrives as
  # {:bad_cert, :selfsigned_peer}, not as an unknown CA.
  describe "a self-signed certificate sent on its own" do
    test "is asked about as {:bad_cert, :selfsigned_peer}, and the answer admits it" do
      test = self()
      %{cert: cert, key: key} = Fixtures.self_signed_device_certificate("peer-verification-device")

      stub(fn :verify_peer, [der, event] ->
        send(test, {:asked, der, event})
        :valid
      end)

      assert {:ok, _socket} = handshake(cert, key)

      assert_receive {:asked, der, {:bad_cert, :selfsigned_peer}}
      assert X509.Certificate.from_der!(der) == cert
    end

    test "is refused when the platform refuses it" do
      %{cert: cert, key: key} = Fixtures.self_signed_device_certificate("peer-verification-device")

      stub(fn :verify_peer, _args -> {:fail, :unknown_device_certificate} end)

      assert {:error, _reason} = handshake(cert, key)
    end
  end

  describe "when the platform cannot be reached" do
    test "the handshake is refused rather than allowed through" do
      stub(fn :verify_peer, _args -> raise "no handler nodes available" end)

      assert {:fail, :platform_unavailable} =
               PeerVerification.verify_fun(certificate(), :valid_peer, :state)
    end

    test "an exit is treated the same way as a raise" do
      stub(fn :verify_peer, _args -> exit(:noconnection) end)

      assert {:fail, :platform_unavailable} =
               PeerVerification.verify_fun(certificate(), :valid_peer, :state)
    end

    test "failure is reported, so an unreachable platform is visible" do
      ref = make_ref()
      test = self()
      handler = "peer-verification-#{inspect(ref)}"

      :telemetry.attach(
        handler,
        [:nerves_hub, :ssl, :unavailable],
        fn _event, _measure, meta, _config -> send(test, {:unavailable, meta}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      stub(fn :verify_peer, _args -> exit(:noconnection) end)

      PeerVerification.verify_fun(certificate(), :valid_peer, :state)

      assert_received {:unavailable, %{kind: :exit, reason: :noconnection}}
    end
  end

  # One TLS handshake from a client presenting `cert`, against a listener that
  # verifies clients with PeerVerification as the device endpoint does. Returns
  # how the handshake ended on the listener's side.
  defp handshake(cert, key) do
    ssl_dir = Path.join(Fixtures.path(), "ssl")

    {:ok, listen} =
      :ssl.listen(0,
        versions: [:"tlsv1.2"],
        verify: :verify_peer,
        verify_fun: {&PeerVerification.verify_fun/3, nil},
        fail_if_no_peer_cert: true,
        certfile: ssl_dir |> Path.join("device.nerves-hub.org.pem") |> to_charlist(),
        keyfile: ssl_dir |> Path.join("device.nerves-hub.org-key.pem") |> to_charlist(),
        cacertfile: ssl_dir |> Path.join("ca.pem") |> to_charlist()
      )

    {:ok, {_address, port}} = :ssl.sockname(listen)

    server =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listen, 5_000)
        :ssl.handshake(socket, 5_000)
      end)

    client =
      :ssl.connect(
        ~c"127.0.0.1",
        port,
        [
          versions: [:"tlsv1.2"],
          verify: :verify_peer,
          cacertfile: ssl_dir |> Path.join("ca.pem") |> to_charlist(),
          server_name_indication: ~c"device.nerves-hub.org",
          cert: X509.Certificate.to_der(cert),
          key: {:ECPrivateKey, X509.PrivateKey.to_der(key)}
        ],
        5_000
      )

    result = Task.await(server)

    with {:ok, socket} <- client, do: :ssl.close(socket)
    :ssl.close(listen)

    result
  end

  # A dispatcher that answers from `fun`, installed the way the real one is.
  defp stub(fun) do
    Application.put_env(:nerves_hub, __MODULE__.Stub, fun)
    Application.put_env(:nerves_hub, Dispatcher, __MODULE__.Stub)
    on_exit(fn -> Application.delete_env(:nerves_hub, __MODULE__.Stub) end)
  end

  defmodule Stub do
    @moduledoc false
    @behaviour Dispatcher

    @impl Dispatcher
    def call(function, args) do
      Application.get_env(:nerves_hub, __MODULE__).(function, args)
    end
  end
end
