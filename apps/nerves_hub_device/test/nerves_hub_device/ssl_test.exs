defmodule NervesHubDevice.SSLTest do
  use NervesHubDevice.DataCase, async: true

  alias NervesHubWebCore.Fixtures

  setup do
    user = Fixtures.user_fixture()

    {:ok,
     %{
       user: user
     }}
  end

  test "verify a certificate", %{user: user} do
    org = Fixtures.org_fixture(user, %{name: "verify_device"})
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)

    identifier = "1234"

    %{cert: ca1, key: ca1_key} = Fixtures.ca_certificate_fixture(org)
    %{cert: ca2, key: ca2_key} = Fixtures.ca_certificate_fixture(org)

    assert ca1 != ca2

    key1 = X509.PrivateKey.new_ec(:secp256r1)
    key2 = X509.PrivateKey.new_ec(:secp256r1)

    cert1 =
      key1
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("CN=#{identifier}", ca1, ca1_key)

    cert2 =
      key2
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("CN=#{identifier}", ca2, ca2_key)

    device1 = Fixtures.device_fixture(org, product, firmware, %{identifier: identifier})
    %{db_cert: _db_cert1} = Fixtures.device_certificate_fixture(device1, cert1)

    device2 = Fixtures.device_fixture(org, product, firmware, %{identifier: identifier})
    %{db_cert: _db_cert2} = Fixtures.device_certificate_fixture(device2, cert2)

    assert {:ok, _db_cert1} = NervesHubDevice.SSL.verify_device(cert1)
    assert {:ok, _db_cert2} = NervesHubDevice.SSL.verify_device(cert2)
  end

  test "refuse a certificate with unknown ca" do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "CN=refuse_conn", template: :root_ca)

    key = X509.PrivateKey.new_ec(:secp256r1)

    cert =
      key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("CN=1234", ca, ca_key)

    assert :error = NervesHubDevice.SSL.verify_device(cert)
  end

  test "refuse a certificate with same serial but unknown signer", %{user: user} do
    org = Fixtures.org_fixture(user, %{name: "refuse_device"})
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)

    identifier = "1234"

    %{cert: ca1, key: ca1_key} = Fixtures.ca_certificate_fixture(org)
    ca2_key = X509.PrivateKey.new_ec(:secp256r1)
    ca2 = X509.Certificate.self_signed(ca2_key, "CN=refuse_conn", template: :root_ca)

    assert ca1 != ca2

    key1 = X509.PrivateKey.new_ec(:secp256r1)
    key2 = X509.PrivateKey.new_ec(:secp256r1)

    cert1 =
      key1
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("CN=#{identifier}", ca1, ca1_key, serial: 999_999)

    cert2 =
      key2
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("CN=#{identifier}", ca2, ca2_key, serial: 999_999)

    device1 = Fixtures.device_fixture(org, product, firmware, %{identifier: identifier})
    %{db_cert: _db_cert1} = Fixtures.device_certificate_fixture(device1, cert1)

    assert {:ok, _db_cert1} = NervesHubDevice.SSL.verify_device(cert1)
    assert :error = NervesHubDevice.SSL.verify_device(cert2)
  end

  test "refuse a certificate with same serial but different validity", %{user: user} do
    org = Fixtures.org_fixture(user, %{name: "refuse_device"})
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)

    identifier = "1234"

    %{cert: ca1, key: ca1_key} = Fixtures.ca_certificate_fixture(org)

    key1 = X509.PrivateKey.new_ec(:secp256r1)

    cert1 =
      key1
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("CN=#{identifier}", ca1, ca1_key, serial: 999_999, validity: 1)

    cert2 =
      key1
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("CN=#{identifier}", ca1, ca1_key, serial: 999_999, validity: 2)

    device1 = Fixtures.device_fixture(org, product, firmware, %{identifier: identifier})
    %{db_cert: _db_cert1} = Fixtures.device_certificate_fixture(device1, cert1)

    assert {:ok, _db_cert1} = NervesHubDevice.SSL.verify_device(cert1)
    assert :error = NervesHubDevice.SSL.verify_device(cert2)
  end

  test "updates DER field when missing", %{user: user} do
    org = Fixtures.org_fixture(user, %{name: "verify_device"})
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)

    identifier = "1234"

    %{cert: ca1, key: ca1_key} = Fixtures.ca_certificate_fixture(org)
    %{cert: ca2, key: ca2_key} = Fixtures.ca_certificate_fixture(org)

    assert ca1 != ca2

    key1 = X509.PrivateKey.new_ec(:secp256r1)
    key2 = X509.PrivateKey.new_ec(:secp256r1)

    cert1 =
      key1
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("CN=#{identifier}", ca1, ca1_key)

    cert2 =
      key2
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("CN=#{identifier}", ca2, ca2_key)

    device1 = Fixtures.device_fixture(org, product, firmware, %{identifier: identifier})
    %{db_cert: db_cert1} = Fixtures.device_certificate_fixture_without_der(device1, cert1)

    device2 = Fixtures.device_fixture(org, product, firmware, %{identifier: identifier})
    %{db_cert: db_cert2} = Fixtures.device_certificate_fixture_without_der(device2, cert2)

    assert is_nil(db_cert1.der)
    assert is_nil(db_cert2.der)

    assert {:ok, db_cert1} = NervesHubDevice.SSL.verify_device(cert1)
    assert {:ok, db_cert2} = NervesHubDevice.SSL.verify_device(cert2)

    assert db_cert1.der == X509.Certificate.to_der(cert1)
    assert db_cert2.der == X509.Certificate.to_der(cert2)
  end

  describe "expired signer certificate" do
    test "reject a first time use certificate", %{user: user} do
      org = Fixtures.org_fixture(user, %{name: "verify_device"})

      not_before = Timex.now() |> Timex.shift(days: -1)
      not_after = Timex.now() |> Timex.shift(seconds: 1)

      template =
        X509.Certificate.Template.new(:root_ca,
          validity: X509.Certificate.Validity.new(not_before, not_after)
        )

      %{cert: ca, key: ca_key} = Fixtures.ca_certificate_fixture(org, template: template)

      key = X509.PrivateKey.new_ec(:secp256r1)

      cert =
        key
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=1234", ca, ca_key)

      :timer.sleep(2_000)

      assert {:fail, :unknown_ca} = NervesHubDevice.SSL.verify_device_certificate(cert, nil)
    end

    test "accept a (n) time use certificate", %{user: user} do
      org = Fixtures.org_fixture(user, %{name: "verify_device"})
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      identifier = "1234"

      not_before = Timex.now() |> Timex.shift(days: -1)
      not_after = Timex.now() |> Timex.shift(seconds: 1)

      template =
        X509.Certificate.Template.new(:root_ca,
          validity: X509.Certificate.Validity.new(not_before, not_after)
        )

      %{cert: ca, key: ca_key} = Fixtures.ca_certificate_fixture(org, template: template)

      key = X509.PrivateKey.new_ec(:secp256r1)

      cert =
        key
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{identifier}", ca, ca_key)

      device = Fixtures.device_fixture(org, product, firmware, %{identifier: identifier})
      %{db_cert: _db_cert} = Fixtures.device_certificate_fixture(device, cert)

      :timer.sleep(2_000)

      assert {:valid, nil} = NervesHubDevice.SSL.verify_device_certificate(cert, nil)
    end

    test "update der on (n) time use certificate", %{user: user} do
      org = Fixtures.org_fixture(user, %{name: "verify_device"})
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      identifier = "1234"

      not_before = Timex.now() |> Timex.shift(days: -1)
      not_after = Timex.now() |> Timex.shift(seconds: 1)

      template =
        X509.Certificate.Template.new(:root_ca,
          validity: X509.Certificate.Validity.new(not_before, not_after)
        )

      %{cert: ca, key: ca_key} = Fixtures.ca_certificate_fixture(org, template: template)

      key = X509.PrivateKey.new_ec(:secp256r1)

      cert =
        key
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{identifier}", ca, ca_key)

      device = Fixtures.device_fixture(org, product, firmware, %{identifier: identifier})
      %{db_cert: db_cert} = Fixtures.device_certificate_fixture_without_der(device, cert)

      :timer.sleep(2_000)

      assert is_nil(db_cert.der)

      assert {:valid, nil} = NervesHubDevice.SSL.verify_device_certificate(cert, nil)

      assert Fixtures.reload(db_cert).der == X509.Certificate.to_der(cert)
    end
  end
end
