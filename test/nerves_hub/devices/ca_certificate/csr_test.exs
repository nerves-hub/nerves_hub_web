defmodule NervesHub.Devices.CACertificate.CSRTest do
  use ExUnit.Case

  alias NervesHub.Accounts.Org
  alias NervesHub.Certificate
  alias NervesHub.Devices.CACertificate.CSR
  alias X509.Certificate.Extension
  alias X509.Certificate.Validity

  @expired Validity.new(~U[2020-01-01 00:00:00Z], ~U[2025-01-01 00:00:00Z])

  @tag :tmp_dir
  test "valid csr", %{tmp_dir: dir} do
    code = CSR.generate_code()

    # generate a CA
    openssl(~w(genrsa -out rootCA.key 2048), dir)

    openssl(
      ~w(req -x509 -sha256 -new -nodes -key rootCA.key -days 3650 -out rootCA.pem -subj /CN=www.nerveshub.org/O=NervesHub/C=US),
      dir
    )

    # Create a csr
    openssl(~w(genrsa -out verificationCert.key 2048), dir)

    openssl(
      ~w(req -new -key verificationCert.key -out verificationCert.csr -subj /CN=#{code}),
      dir
    )

    openssl(
      ~w(x509 -req -in verificationCert.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out verificationCert.crt -days 500 -sha256),
      dir
    )

    {:ok, cert_pem} = File.read(Path.join(dir, "rootCA.pem"))
    {:ok, csr_pem} = File.read(Path.join(dir, "verificationCert.crt"))
    {:ok, csr} = Certificate.from_pem(csr_pem)
    {:ok, cert} = Certificate.from_pem(cert_pem)
    assert :ok = CSR.validate_csr(code, cert, csr)
  end

  @tag :tmp_dir
  test "invalid csr", %{tmp_dir: dir} do
    code = CSR.generate_code()

    openssl(~w(genrsa -out rootCA.key 2048), dir)

    openssl(
      ~w(req -x509 -sha256 -new -nodes -key rootCA.key -days 3650 -out rootCA.pem -subj /CN=www.nerveshub.org/O=NervesHub/C=US),
      dir
    )

    openssl(~w(genrsa -out verificationCert.key 2048), dir)

    # the CN= value *should* be the `code`. Set it to a different string so the check fails
    openssl(
      ~w(req -new -key verificationCert.key -out verificationCert.csr -subj /CN=oops),
      dir
    )

    openssl(
      ~w(x509 -req -in verificationCert.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out verificationCert.crt -days 500 -sha256),
      dir
    )

    {:ok, cert_pem} = File.read(Path.join(dir, "rootCA.pem"))
    {:ok, csr_pem} = File.read(Path.join(dir, "verificationCert.crt"))
    {:ok, csr} = Certificate.from_pem(csr_pem)
    {:ok, cert} = Certificate.from_pem(cert_pem)
    assert {:error, :invalid_csr} = CSR.validate_csr(code, cert, csr)
  end

  describe "validate_cert_ownership/3" do
    setup do
      org = %Org{id: 1, name: "acme"}
      ca_key = X509.PrivateKey.new_ec(:secp256r1)

      %{org: org, ca_key: ca_key, ca: root_ca(ca_key), token: CSR.generate_verification_token(org)}
    end

    test "accepts a verification certificate the CA signed", %{org: org, ca: ca, ca_key: ca_key, token: token} do
      assert :ok = CSR.validate_cert_ownership(org, ca, verification_cert(token, ca, ca_key))
    end

    test "accepts a CA that has expired", %{org: org, ca_key: ca_key, token: token} do
      ca = root_ca(ca_key, validity: @expired)

      assert :ok = CSR.validate_cert_ownership(org, ca, verification_cert(token, ca, ca_key))
    end

    test "refuses a verification certificate that has expired", %{org: org, ca: ca, ca_key: ca_key, token: token} do
      verification_cert = verification_cert(token, ca, ca_key, validity: @expired)

      assert {:error, {:invalid_csr, :verification_cert_expired}} =
               CSR.validate_cert_ownership(org, ca, verification_cert)
    end

    test "refuses a verification certificate another key signed", %{org: org, ca: ca, token: token} do
      other_key = X509.PrivateKey.new_ec(:secp256r1)
      verification_cert = verification_cert(token, root_ca(other_key), other_key)

      assert {:error, {:invalid_csr, :not_signed_by_ca}} = CSR.validate_cert_ownership(org, ca, verification_cert)
    end

    test "refuses a verification certificate without the SAN", %{org: org, ca: ca, ca_key: ca_key} do
      verification_cert =
        X509.PrivateKey.new_ec(:secp256r1)
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("/CN=certificate-verification", ca, ca_key)

      assert {:error, {:invalid_csr, :missing_verification_san}} =
               CSR.validate_cert_ownership(org, ca, verification_cert)
    end

    test "refuses a code NervesHub did not issue", %{org: org, ca: ca, ca_key: ca_key} do
      assert {:error, {:invalid_csr, :invalid_verification_token}} =
               CSR.validate_cert_ownership(org, ca, verification_cert("oops", ca, ca_key))
    end

    test "refuses a code over an hour old", %{org: org, ca: ca, ca_key: ca_key} do
      token =
        Phoenix.Token.sign(NervesHubWeb.Endpoint, "ca_certificate", "#{org.id}-#{org.name}",
          signed_at: System.system_time(:second) - 2 * 60 * 60
        )

      assert {:error, {:invalid_csr, :expired_verification_token}} =
               CSR.validate_cert_ownership(org, ca, verification_cert(token, ca, ca_key))
    end

    test "refuses a code issued for another org", %{org: org, ca: ca, ca_key: ca_key} do
      token = CSR.generate_verification_token(%Org{id: 2, name: "someone-else"})

      assert {:error, {:invalid_csr, :verification_token_for_another_org}} =
               CSR.validate_cert_ownership(org, ca, verification_cert(token, ca, ca_key))
    end
  end

  defp root_ca(key, opts \\ []) do
    X509.Certificate.self_signed(key, "CN=Root CA", Keyword.put(opts, :template, :root_ca))
  end

  # A verification certificate carrying `token`, signed by `ca`
  defp verification_cert(token, ca, ca_key, opts \\ []) do
    san = Extension.subject_alt_name(uniformResourceIdentifier: ~c"urn:nerveshub:verify:#{token}")

    X509.PrivateKey.new_ec(:secp256r1)
    |> X509.PublicKey.derive()
    |> X509.Certificate.new(
      "/CN=certificate-verification",
      ca,
      ca_key,
      Keyword.put(opts, :extensions, subject_alt_name: san)
    )
  end

  defp openssl(args, dir) do
    {_, 0} = System.cmd("openssl", args, cd: dir, stderr_to_stdout: true, env: [])
    :ok
  end
end
