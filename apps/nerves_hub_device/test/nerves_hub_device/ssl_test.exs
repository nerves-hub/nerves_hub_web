defmodule NervesHubDevice.SSLTest do
  use NervesHubDevice.DataCase, async: true

  alias NervesHubWebCore.{Certificate, Devices, Fixtures}

  require X509.ASN1

  setup :build_db_records
  setup :build_certs

  describe "known certificate" do
    setup context do
      Fixtures.device_certificate_fixture(context.device, context.cert)
    end

    test "verifies on :valid_peer event", %{cert: cert, db_cert: db_cert} do
      assert is_nil(db_cert.last_used)
      assert {:valid, _state} = run_verify(cert, :valid_peer)
      refute is_nil(Fixtures.reload(db_cert).last_used)
    end

    test "verifies on {:bad_cert, :unknown_ca} event", %{cert: cert, db_cert: db_cert} do
      assert is_nil(db_cert.last_used)
      assert {:valid, _state} = run_verify(cert, {:bad_cert, :unknown_ca})
      refute is_nil(Fixtures.reload(db_cert).last_used)
    end

    test "verifies multiple certs with same public key", context do
      otp_cert =
        X509.Certificate.new(
          context.public_key,
          "/O=#{context.org.name}/CN=#{context.device.identifier}",
          context.ca_cert,
          context.ca_key
        )

      %{db_cert: db_cert2} = Fixtures.device_certificate_fixture(context.device, otp_cert)

      assert is_nil(context.db_cert.last_used)
      assert {:valid, _state} = run_verify(otp_cert)
      refute is_nil(Fixtures.reload(db_cert2).last_used)
      assert is_nil(context.db_cert.last_used)
    end

    # TODO: Support cert expiration and test here

    test "verifies when signer CA is expired", context do
      expired_ca = do_corruption(context.unknown_signer, :expired)
      {:ok, _db_ca} = Devices.create_ca_certificate_from_x509(context.org, expired_ca)

      %{db_cert: _db_cert} =
        Fixtures.device_certificate_fixture(context.device, context.unknown_cert)

      assert {:valid, _} = run_verify(context.unknown_cert)
    end

    test "rejects cert with corrupted signature, but serial, aki, and ski still match", context do
      corrupted = do_corruption(context.cert, :bad_signature)
      assert {:fail, :invalid_signature} = run_verify(corrupted)
    end

    test "saves DER and fingerprints when missing", context do
      {:ok, _db_ca} = Devices.create_ca_certificate_from_x509(context.org, context.unknown_signer)

      %{db_cert: db_cert} =
        Fixtures.device_certificate_fixture_without_der(context.device, context.unknown_cert)

      assert is_nil(db_cert.der)
      assert is_nil(db_cert.fingerprint)
      assert is_nil(db_cert.public_key_fingerprint)

      assert {:valid, _state} = run_verify(context.unknown_cert)

      reloaded = Fixtures.reload(db_cert)

      assert reloaded.der == Certificate.to_der(context.unknown_cert)
      assert reloaded.fingerprint == Certificate.fingerprint(context.unknown_cert)

      assert reloaded.public_key_fingerprint ==
               Certificate.public_key_fingerprint(context.unknown_cert)
    end

    test "jitp", _ do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user, %{name: "jitp_verify_device"})
      product = Fixtures.product_fixture(user, org)
      ca = Fixtures.ca_certificate_fixture(org)
      identifier = "jitp_device"

      subject_rdn = "/O=#{org.name}/CN=#{identifier}"

      public_key =
        X509.PrivateKey.new_ec(:secp256r1)
        |> X509.PublicKey.derive()

      otp_cert = X509.Certificate.new(public_key, subject_rdn, ca.cert, ca.key)

      # Enable JITP
      jitp =
        %Devices.CACertificate.JITP{
          product_id: product.id,
          tags: ["hello", "jitp"],
          description: "jitp"
        }
        |> NervesHubWebCore.Repo.insert!()

      ca.db_cert
      |> NervesHubWebCore.Repo.preload([:org, :jitp])
      |> Ecto.Changeset.change(%{jitp_id: jitp.id})
      |> NervesHubWebCore.Repo.update!()

      assert Devices.get_device_by_identifier(org, identifier) == {:error, :not_found}
      assert {:valid, _state} = run_verify(otp_cert, {:bad_cert, :unknown_ca})
      assert {:ok, device} = Devices.get_device_by_identifier(org, identifier)
      assert device.identifier == identifier
      assert device.description == "jitp"
      assert device.product_id == product.id
      assert device.tags == ["hello", "jitp"]
    end
  end

  describe "known public key" do
    setup context do
      cert2 =
        X509.Certificate.new(
          context.public_key,
          "/CN=#{context.device.identifier}",
          context.ca_cert,
          context.ca_key
        )

      Fixtures.device_certificate_fixture(context.device, context.cert)
      |> Map.take([:db_cert])
      |> Map.put(:cert2, cert2)
    end

    test "rejects when common name does not match device identifier", context do
      new_cert =
        X509.Certificate.new(
          context.public_key,
          "/CN=#{context.device.identifier}+wat!?",
          context.ca_cert,
          context.ca_key
        )

      assert {:fail, :mismatched_cert} = run_verify(new_cert)
    end

    test "rejects unknown Signer CA", context do
      {:ok, _} = Devices.delete_ca_certificate(context.ca_db_cert)

      assert {:fail, :unknown_ca} = run_verify(context.cert2)
    end

    test "rejects Signer CA from another org", context do
      {:ok, _} = Devices.delete_ca_certificate(context.ca_db_cert)
      new_org = Fixtures.org_fixture(context.user, %{name: "New-Org"})
      {:ok, _db_ca} = Devices.create_ca_certificate_from_x509(new_org, context.ca_cert)

      assert {:fail, :mismatched_org} = run_verify(context.cert2)
    end

    test "rejects registering expired device cert", context do
      expired = do_corruption(context.cert2, :expired)
      assert {:fail, :cert_expired} = run_verify(expired)
    end

    test "rejects registering when signature bad", context do
      bad_signature = do_corruption(context.cert2, :bad_signature)

      assert {:fail, :invalid_signature} = run_verify(bad_signature)
    end

    test "rejects registering when signer CA expired", context do
      {:ok, _} = Devices.delete_ca_certificate(context.ca_db_cert)
      expired_ca = do_corruption(context.ca_cert, :expired)
      {:ok, db_ca} = Devices.create_ca_certificate_from_x509(context.org, expired_ca)
      assert is_nil(db_ca.last_used)
      assert {:fail, :invalid_issuer} = run_verify(context.cert2)
      refute is_nil(Fixtures.reload(db_ca).last_used)
    end

    # TODO: Test registering with expired signer if allowed

    test "registers a valid certificate", context do
      assert {:error, :not_found} = Devices.get_device_certificate_by_x509(context.cert2)
      assert {:valid, _} = run_verify(context.cert2)
      assert {:ok, _db_cert} = Devices.get_device_certificate_by_x509(context.cert2)
    end
  end

  describe "unknown public key" do
    test "rejects bad or missing common name", context do
      no_cn_otp_cert =
        X509.PrivateKey.new_ec(:secp256r1)
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("/O=#{context.org.name}", context.ca_cert, context.ca_key)

      empty_cn_otp_cert =
        X509.PrivateKey.new_ec(:secp256r1)
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("/O=#{context.org.name}/CN=", context.ca_cert, context.ca_key)

      assert {:fail, :missing_common_name} = run_verify(no_cn_otp_cert)
      assert {:fail, :missing_common_name} = run_verify(empty_cn_otp_cert)
    end

    test "rejects cert from unknown Signer CA", context do
      assert {:fail, :unknown_ca} = run_verify(context.unknown_cert)
    end

    test "rejects registering expired device cert", context do
      expired = do_corruption(context.cert, :expired)
      assert {:fail, :cert_expired} = run_verify(expired)
    end

    test "rejects registering when signer CA expired", context do
      expired_ca = do_corruption(context.unknown_signer, :expired)
      {:ok, db_ca} = Devices.create_ca_certificate_from_x509(context.org, expired_ca)
      assert is_nil(db_ca.last_used)
      assert {:fail, :invalid_issuer} = run_verify(context.unknown_cert)
      refute is_nil(Fixtures.reload(db_ca).last_used)
    end

    # TODO: Test registering with expired signer if allowed

    test "rejects registering when signature bad", context do
      bad_signature = do_corruption(context.cert, :bad_signature)

      assert {:fail, :invalid_signature} = run_verify(bad_signature)
    end

    test "rejects registering when device does not exist", context do
      no_device_otp_cert =
        X509.PrivateKey.new_ec(:secp256r1)
        |> X509.PublicKey.derive()
        |> X509.Certificate.new(
          "/O=#{context.org.name}/CN=WhoDer?!",
          context.ca_cert,
          context.ca_key
        )

      assert {:fail, :device_not_registered} = run_verify(no_device_otp_cert)
    end

    test "rejects registering when device has a different public key", context do
      # Save a cert and public key
      %{db_cert: _} = Fixtures.device_certificate_fixture(context.device, context.cert)

      # Make new CA known
      {:ok, _db_ca} = Devices.create_ca_certificate_from_x509(context.org, context.unknown_signer)

      # Use known CA which is a different public key
      assert {:fail, :unexpected_pubkey} = run_verify(context.unknown_cert)
    end

    test "registers a valid certificate", context do
      assert {:error, :not_found} = Devices.get_device_certificate_by_x509(context.cert)
      assert {:valid, _} = run_verify(context.cert)
      assert {:ok, _db_cert} = Devices.get_device_certificate_by_x509(context.cert)
    end
  end

  test "refuse a certificate with same serial but different validity", context do
    %{db_cert: _} = Fixtures.device_certificate_fixture(context.device, context.cert)
    serial = X509.Certificate.serial(context.cert)
    subject_rdn = "/CN=#{context.device.identifier}"

    new_cert_known_key =
      X509.Certificate.new(context.public_key, subject_rdn, context.ca_cert, context.ca_key,
        serial: serial,
        validity: 3
      )

    assert {:fail, :registration_failed} = run_verify(new_cert_known_key)
  end

  defp run_verify(otp_cert, event \\ :valid_peer) do
    NervesHubDevice.SSL.verify_fun(otp_cert, event, nil)
  end

  defp build_db_records(_context) do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user, %{name: "verify_device"})
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    ca_fix = Fixtures.ca_certificate_fixture(org)
    device = Fixtures.device_fixture(org, product, firmware)

    %{
      ca_cert: ca_fix.cert,
      ca_key: ca_fix.key,
      ca_db_cert: ca_fix.db_cert,
      device: device,
      firmware: firmware,
      org: org,
      org_key: org_key,
      product: product,
      user: user
    }
  end

  defp build_certs(context) do
    subject_rdn = "/O=#{context.org.name}/CN=#{context.device.identifier}"

    public_key =
      X509.PrivateKey.new_ec(:secp256r1)
      |> X509.PublicKey.derive()

    otp_cert = X509.Certificate.new(public_key, subject_rdn, context.ca_cert, context.ca_key)

    unknown_ca_key = X509.PrivateKey.new_ec(:secp256r1)

    unknown_ca_cert =
      X509.Certificate.self_signed(unknown_ca_key, "CN=refuse_conn", template: :root_ca)

    unknown_cert =
      X509.PrivateKey.new_ec(:secp256r1)
      |> X509.PublicKey.derive()
      |> X509.Certificate.new(subject_rdn, unknown_ca_cert, unknown_ca_key)

    %{
      cert: otp_cert,
      public_key: public_key,
      unknown_cert: unknown_cert,
      unknown_signer: unknown_ca_cert
    }
  end

  defp do_corruption(cert, :expired) do
    {:ok, not_before, 0} = DateTime.from_iso8601("2018-01-01T00:00:00Z")
    {:ok, not_after, 0} = DateTime.from_iso8601("2018-12-31T23:59:59Z")
    new_validity = X509.Certificate.Validity.new(not_before, not_after)

    tbs_cert = X509.ASN1.otp_certificate(cert, :tbsCertificate)
    new_tbs_cert = X509.ASN1.tbs_certificate(tbs_cert, validity: new_validity)

    X509.ASN1.otp_certificate(cert, tbsCertificate: new_tbs_cert)
  end

  defp do_corruption(cert, :bad_signature) do
    corrupted_signature =
      X509.ASN1.otp_certificate(cert, :signature)
      |> flip_bit()

    X509.ASN1.otp_certificate(cert, signature: corrupted_signature)
  end

  defp flip_bit(bin) do
    len = byte_size(bin) - 1
    <<a::binary-size(len), b::7, c::1>> = bin
    flipped = if c == 1, do: 0, else: 1
    <<a::binary, b::7, flipped::1>>
  end
end
