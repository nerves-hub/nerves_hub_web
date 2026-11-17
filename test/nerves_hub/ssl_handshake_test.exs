defmodule NervesHub.SSLHandshakeTest do
  @moduledoc """
  `NervesHub.SSL` over a real TLS handshake, for what only `:ssl` can show: what
  it does with the reason a certificate is refused for.
  """

  # The handshake runs in a process :ssl starts, which can only reach the
  # sandbox in shared mode.
  use NervesHub.DataCase, async: false

  alias NervesHub.DeviceLink.PeerVerification
  alias NervesHub.Devices.CACertificates
  alias NervesHub.Devices.Certificates
  alias NervesHub.Fixtures

  setup do
    test = self()
    handler = "ssl-handshake-#{inspect(make_ref())}"

    :telemetry.attach(
      handler,
      [:nerves_hub, :ssl, :fail],
      fn _event, _measure, meta, _config -> send(test, {:ssl_fail, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  # Refused as :unknown_ca, :ssl took the certificate to have no trust anchor and
  # looked for another root. It found the same one and asked again, without end,
  # long after the device had gone. This happens when the endpoint trusts the
  # root, through DEVICE_SSL_CACERTFILE or the public roots in CAStore, but no
  # CA in the chain is registered.
  test "refuses a certificate from a trusted root that is not registered, and asks once" do
    root_key = X509.PrivateKey.new_ec(:secp256r1)
    root = X509.Certificate.self_signed(root_key, "/CN=Unregistered Signer Root", template: :root_ca)

    device_key = X509.PrivateKey.new_ec(:secp256r1)

    cert =
      device_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("/CN=unregistered-signer-device", root, root_key)

    assert {:error, {:tls_alert, {:handshake_failure, _}}} = handshake([cert], device_key, trusting: root)

    assert_receive {:ssl_fail, %{reason: :ca_not_registered}}
    refute_receive {:ssl_fail, _}, 200
  end

  # How a public root in CAStore is reached: through an intermediate the client
  # sends with its own certificate.
  test "refuses a certificate through an intermediate under a trusted root, and asks once" do
    root_key = X509.PrivateKey.new_ec(:secp256r1)
    root = X509.Certificate.self_signed(root_key, "/CN=Public Root", template: :root_ca)

    intermediate_key = X509.PrivateKey.new_ec(:secp256r1)

    intermediate =
      intermediate_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("/CN=Public Intermediate", root, root_key, template: :ca)

    device_key = X509.PrivateKey.new_ec(:secp256r1)

    cert =
      device_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("/CN=unregistered-intermediate-device", intermediate, intermediate_key)

    assert {:error, {:tls_alert, {:handshake_failure, _}}} =
             handshake([cert, intermediate], device_key, trusting: root)

    assert_receive {:ssl_fail, %{reason: :ca_not_registered}}
    refute_receive {:ssl_fail, _}, 200
  end

  # The workaround for versions without the fix: a trust store that holds no
  # root a device chain can reach, so that :ssl never finds a trust anchor to try
  # again. Devices still connect through the CAs registered in NervesHub, which
  # is how they connect whenever their root isn't in the trust store.
  describe "with a trust store that holds no device roots" do
    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user, %{name: "handshake_trust_store"})
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)
      ca = Fixtures.ca_certificate_fixture(org)

      unrelated =
        X509.PrivateKey.new_ec(:secp256r1)
        |> X509.Certificate.self_signed("/CN=Unrelated Root", template: :root_ca)

      device_key = X509.PrivateKey.new_ec(:secp256r1)

      %{ca: ca, device: device, device_key: device_key, org: org, unrelated: unrelated}
    end

    test "admits a device whose certificate is on file", context do
      cert = device_cert(context, context.ca.cert, context.ca.key)
      Fixtures.device_certificate_fixture(context.device, cert)

      assert {:ok, _socket} = handshake([cert], context.device_key, trusting: context.unrelated)
      refute_received {:ssl_fail, _}
    end

    test "registers a new certificate from a registered CA, sent on its own", context do
      cert = device_cert(context, context.ca.cert, context.ca.key)

      assert {:ok, _socket} = handshake([cert], context.device_key, trusting: context.unrelated)
      assert {:ok, _db_cert} = Certificates.get_device_certificate_by_x509(cert)
      refute_received {:ssl_fail, _}
    end

    test "registers a new certificate from a registered CA, sent with the CA", context do
      cert = device_cert(context, context.ca.cert, context.ca.key)

      assert {:ok, _socket} = handshake([cert, context.ca.cert], context.device_key, trusting: context.unrelated)
      assert {:ok, _db_cert} = Certificates.get_device_certificate_by_x509(cert)
      refute_received {:ssl_fail, _}
    end

    test "registers a new certificate from a registered intermediate under an unknown root", context do
      root_key = X509.PrivateKey.new_ec(:secp256r1)
      root = X509.Certificate.self_signed(root_key, "/CN=Unregistered Root", template: :root_ca)
      intermediate_key = X509.PrivateKey.new_ec(:secp256r1)

      intermediate =
        intermediate_key
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("/CN=Registered Intermediate", root, root_key, template: :ca)

      {:ok, _db_ca} = CACertificates.create_ca_certificate_from_x509(context.org, intermediate)
      cert = device_cert(context, intermediate, intermediate_key)

      assert {:ok, _socket} = handshake([cert, intermediate], context.device_key, trusting: context.unrelated)
      assert {:ok, _db_cert} = Certificates.get_device_certificate_by_x509(cert)
      refute_received {:ssl_fail, _}
    end

    test "refuses a certificate from an unregistered CA, and asks once", context do
      root_key = X509.PrivateKey.new_ec(:secp256r1)
      root = X509.Certificate.self_signed(root_key, "/CN=Unregistered Root", template: :root_ca)
      cert = device_cert(context, root, root_key)

      assert {:error, {:tls_alert, _}} = handshake([cert, root], context.device_key, trusting: context.unrelated)

      assert_receive {:ssl_fail, %{reason: :ca_not_registered}}
      refute_receive {:ssl_fail, _}, 200
    end
  end

  defp device_cert(context, signer, signer_key) do
    context.device_key
    |> X509.PublicKey.derive()
    |> X509.Certificate.new("/O=#{context.org.name}/CN=#{context.device.identifier}", signer, signer_key)
  end

  # One TLS handshake from a device presenting `chain`, its own certificate
  # first, against a listener that trusts only `root` and verifies clients with PeerVerification, as the device
  # endpoint does. Returns how it ended on the listener's side, or
  # :never_finished. A handshake process stuck inside path validation never sees
  # its own timeout, so :ssl.handshake/2 would wait for it forever.
  defp handshake(chain, key, trusting: root) do
    ssl_dir = Path.join(Fixtures.path(), "ssl")

    {:ok, listen} =
      :ssl.listen(0,
        versions: [:"tlsv1.2"],
        verify: :verify_peer,
        verify_fun: {&PeerVerification.verify_fun/3, nil},
        fail_if_no_peer_cert: false,
        certfile: ssl_dir |> Path.join("device.nerves-hub.org.pem") |> to_charlist(),
        keyfile: ssl_dir |> Path.join("device.nerves-hub.org-key.pem") |> to_charlist(),
        cacerts: [X509.Certificate.to_der(root)]
      )

    {:ok, {_address, port}} = :ssl.sockname(listen)

    server =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listen, 5_000)
        :ssl.handshake(socket, 2_000)
      end)

    client =
      :ssl.connect(
        ~c"127.0.0.1",
        port,
        [
          versions: [:"tlsv1.2"],
          verify: :verify_none,
          cert: Enum.map(chain, &X509.Certificate.to_der/1),
          key: {:ECPrivateKey, X509.PrivateKey.to_der(key)}
        ],
        2_000
      )

    result =
      case Task.yield(server, 3_000) || Task.shutdown(server, :brutal_kill) do
        {:ok, result} -> result
        nil -> :never_finished
      end

    with {:ok, socket} <- client, do: :ssl.close(socket)
    :ssl.close(listen)

    result
  end
end
