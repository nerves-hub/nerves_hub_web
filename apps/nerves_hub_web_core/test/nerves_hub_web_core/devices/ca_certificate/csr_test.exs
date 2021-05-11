defmodule NervesHubWebCore.Devices.CACertificate.CSRTest do
  use ExUnit.Case
  alias NervesHubWebCore.Devices.CACertificate.CSR
  alias NervesHubWebCore.Certificate

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

  defp openssl(args, dir) do
    {_, 0} = System.cmd("openssl", args, cd: dir, stderr_to_stdout: true)
  end
end
