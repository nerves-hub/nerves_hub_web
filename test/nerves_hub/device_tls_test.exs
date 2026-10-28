defmodule NervesHub.DeviceTLSTest do
  @moduledoc """
  Checking a keypair, and putting it in front of new handshakes.

  Nothing restarts to undo a bad install, so every check is a keypair that
  would otherwise sit in the listener failing every handshake. And the swap
  itself has to reach new handshakes without disturbing the connections the
  listener already holds -- that is the whole reason for it.
  """

  use ExUnit.Case, async: true

  alias NervesHub.DeviceTLS
  alias X509.Certificate.Extension

  @moduletag :tmp_dir

  @host "devices.example.test"

  setup do
    root_key = X509.PrivateKey.new_ec(:secp256r1)
    root = X509.Certificate.self_signed(root_key, "/CN=Test Root", template: :root_ca)

    %{root: root, root_key: root_key, pair: leaf(root, root_key, @host)}
  end

  defp leaf(root, root_key, host, opts \\ []) do
    key = X509.PrivateKey.new_ec(:secp256r1)

    cert =
      key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new(
        "/CN=#{host}",
        root,
        root_key,
        [extensions: [subject_alt_name: Extension.subject_alt_name([host])]] ++
          opts
      )

    %{
      key_pem: X509.PrivateKey.to_pem(key),
      chain_pem: X509.Certificate.to_pem(cert) <> X509.Certificate.to_pem(root),
      cert: cert
    }
  end

  describe "check/4" do
    test "accepts a matching keypair for the host", %{pair: pair} do
      assert {:ok, summary} = DeviceTLS.check(pair.key_pem, pair.chain_pem, @host)
      assert summary.subject == "CN=#{@host}", "the subject is logged on every install"

      assert summary.sha1 ==
               :crypto.hash(:sha, X509.Certificate.to_der(pair.cert))
               |> Base.encode16(case: :lower),
             "the sha1 has to be the leaf's, which providers compare against, or nothing is ever unchanged"
    end

    test "accepts RSA as well as EC", %{root: root, root_key: root_key} do
      key = X509.PrivateKey.new_rsa(2048)

      cert =
        key |> X509.PublicKey.derive() |> X509.Certificate.new("/CN=#{@host}", root, root_key)

      assert {:ok, _} =
               DeviceTLS.check(
                 X509.PrivateKey.to_pem(key),
                 X509.Certificate.to_pem(cert),
                 nil
               )
    end

    test "refuses a key that is not the certificate's", %{pair: pair} do
      other = X509.PrivateKey.new_ec(:secp256r1) |> X509.PrivateKey.to_pem()

      assert {:error, "the private key does not match" <> _} =
               DeviceTLS.check(other, pair.chain_pem, @host)
    end

    test "refuses a chain with the issuer first", %{pair: pair, root: root} do
      reversed = X509.Certificate.to_pem(root) <> X509.Certificate.to_pem(pair.cert)

      # The root comes first, so it is the root the key is checked against.
      assert {:error, _} = DeviceTLS.check(pair.key_pem, reversed, @host)
    end

    test "refuses a chain out of order past the leaf", %{pair: pair} do
      unrelated = X509.Certificate.self_signed(X509.PrivateKey.new_ec(:secp256r1), "/CN=Other")
      chain = X509.Certificate.to_pem(pair.cert) <> X509.Certificate.to_pem(unrelated)

      assert {:error, "the chain is out of order" <> _} =
               DeviceTLS.check(pair.key_pem, chain, @host)
    end

    test "refuses a certificate for another host", %{pair: pair} do
      assert {:error, "the certificate does not cover other.example.test"} =
               DeviceTLS.check(pair.key_pem, pair.chain_pem, "other.example.test")
    end

    test "takes a wildcard for any name under it", %{root: root, root_key: root_key} do
      pair = leaf(root, root_key, "*.example.test")
      assert {:ok, _} = DeviceTLS.check(pair.key_pem, pair.chain_pem, @host)
    end

    test "refuses an expired certificate, and one not yet valid", %{pair: pair} do
      assert {:error, "the certificate expired" <> _} =
               DeviceTLS.check(pair.key_pem, pair.chain_pem, @host, ~U[2099-01-01 00:00:00Z])

      assert {:error, "the certificate is not valid until" <> _} =
               DeviceTLS.check(pair.key_pem, pair.chain_pem, @host, ~U[2000-01-01 00:00:00Z])
    end

    test "refuses an encrypted key, or none", %{pair: pair} do
      key = X509.PrivateKey.new_ec(:secp256r1) |> X509.PrivateKey.to_pem(password: "secret")

      assert {:error, "the private key is encrypted"} =
               DeviceTLS.check(key, pair.chain_pem, @host)

      assert {:error, "there is no private key"} = DeviceTLS.check("", pair.chain_pem, @host)
      assert {:error, "there are no certificates"} = DeviceTLS.check(pair.key_pem, "", @host)
    end
  end

  describe "install/3" do
    test "writes one file only this user can read", %{tmp_dir: dir, pair: pair} do
      path = Path.join(dir, "device_tls.pem")
      assert :ok = DeviceTLS.install(path, pair.key_pem, pair.chain_pem)

      assert %File.Stat{mode: mode} = File.stat!(path)
      assert Bitwise.band(mode, 0o777) == 0o600, "the file holds the private key"
      assert File.ls!(dir) == ["device_tls.pem"], "nothing temporary should be left beside it"

      assert DeviceTLS.installed_sha1(path) ==
               elem(DeviceTLS.check(pair.key_pem, pair.chain_pem, nil), 1).sha1
    end

    test "has nothing installed when the file is missing or empty", %{tmp_dir: dir} do
      assert DeviceTLS.installed_sha1(Path.join(dir, "missing.pem")) == nil
      File.write!(Path.join(dir, "empty.pem"), "")
      assert DeviceTLS.installed_sha1(Path.join(dir, "empty.pem")) == nil
    end

    test "a running listener serves the new certificate, and keeps its connections",
         %{tmp_dir: dir, pair: old, root: root, root_key: root_key} do
      path = Path.join(dir, "device_tls.pem")
      :ok = DeviceTLS.install(path, old.key_pem, old.chain_pem)

      # As the device endpoint is configured: one file as both.
      {:ok, listen} =
        :ssl.listen(0, keyfile: path, certfile: path, reuseaddr: true, active: false)

      {:ok, {_, port}} = :ssl.sockname(listen)
      test = self()

      spawn_link(fn -> accept(listen, test) end)

      held = connect(port)
      assert peer(held) == X509.Certificate.to_der(old.cert)

      new = leaf(root, root_key, @host)
      :ok = DeviceTLS.install(path, new.key_pem, new.chain_pem)

      assert peer(connect(port)) == X509.Certificate.to_der(new.cert),
             "a handshake after the install still got the old certificate"

      assert {:ok, _} = :ssl.connection_information(held),
             "installing a certificate must not touch established connections"
    end
  end

  # Holds each accepted connection open until its client hangs up.
  defp accept(listen, test) do
    {:ok, transport} = :ssl.transport_accept(listen)

    spawn(fn ->
      with {:ok, _socket} <- :ssl.handshake(transport, 5_000), do: Process.sleep(:infinity)
    end)

    accept(listen, test)
  end

  defp connect(port) do
    {:ok, socket} =
      :ssl.connect(~c"localhost", port, [verify: :verify_none, active: false], 5_000)

    socket
  end

  defp peer(socket) do
    {:ok, der} = :ssl.peercert(socket)
    der
  end
end
