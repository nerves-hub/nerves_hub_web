defmodule NervesHub.DeviceTLS.RuntimeConfigTest do
  @moduledoc """
  What `config/runtime.exs` makes of the device endpoint's TLS settings in
  production.

  The rest of the suite reads `config/test.exs`, which cannot show that an
  environment variable reaches the listener. These evaluate the real file, as
  a release would at boot, on a device node.
  """

  # Sets OS environment variables, which every process shares.
  use ExUnit.Case, async: false

  alias NervesHub.DeviceTLS
  alias NervesHub.DeviceTLS.Cluster
  alias NervesHub.DeviceTLS.Reloader

  @moduletag :tmp_dir

  # Everything the production block needs to evaluate on a device node: TLS
  # material as paths rather than base64, which would be written out under
  # /app, and a database it never connects to.
  setup %{tmp_dir: dir} do
    keyfile = dir |> Path.join("key.pem") |> tap(&File.write!(&1, ""))
    certfile = dir |> Path.join("cert.pem") |> tap(&File.write!(&1, ""))

    %{
      env: %{
        "NERVES_HUB_APP" => "device",
        "DEVICE_HOST" => "devices.example.test",
        "SECRET_KEY_BASE" => String.duplicate("a", 64),
        "DATABASE_URL" => "postgres://user:pass@localhost/nerves_hub",
        "DATABASE_SSL" => "false",
        "FIRMWARE_UPLOAD_PATH" => Path.join(dir, "uploads"),
        "DEVICE_SSL_KEYFILE" => keyfile,
        "DEVICE_SSL_CERTFILE" => certfile,
        "DEVICE_SSL_KEY" => nil,
        "DEVICE_SSL_CERT" => nil,
        "DEVICE_TLS_FROM_CLUSTER" => nil,
        "DEVICE_TLS_PEMFILE" => Path.join(dir, "device_tls.pem"),
        "DEVICE_TLS_POLL_INTERVAL" => nil,
        "DEVICE_TLS_BOOT_TIMEOUT" => nil
      }
    }
  end

  test "is off unless asked for, serving the keypair as given", %{env: env} do
    options = transport_options(env)

    assert options[:keyfile] == env["DEVICE_SSL_KEYFILE"]
    assert options[:certfile] == env["DEVICE_SSL_CERTFILE"]
    refute app_config(env)[Reloader]
  end

  test "listens on the one file the reloader replaces", %{env: env} do
    env = %{env | "DEVICE_TLS_FROM_CLUSTER" => "true"}
    options = transport_options(env)

    assert options[:certfile] == env["DEVICE_TLS_PEMFILE"]

    assert options[:keyfile] == env["DEVICE_TLS_PEMFILE"], """
    Key and certificate in two files cannot be replaced together by a single
    rename, so a handshake could read a new certificate with the old key.
    """

    reloader = app_config(env)[Reloader]
    assert reloader[:source] == {Cluster, []}
    assert reloader[:certfile] == env["DEVICE_TLS_PEMFILE"]
    assert reloader[:host] == "devices.example.test"
    assert reloader[:interval] == to_timeout(minute: 5)
    assert reloader[:boot_timeout] == to_timeout(minute: 2)
  end

  test "gets past Bandit's check of the options, and listens", %{env: env} do
    key = X509.PrivateKey.new_ec(:secp256r1)
    cert = X509.Certificate.self_signed(key, "/CN=devices.example.test")
    env = %{env | "DEVICE_TLS_FROM_CLUSTER" => "true"}

    :ok =
      DeviceTLS.install(
        env["DEVICE_TLS_PEMFILE"],
        X509.PrivateKey.to_pem(key),
        X509.Certificate.to_pem(cert)
      )

    # What Bandit does with them before it starts the listener. :ssl alone
    # would take a certfile with no keyfile; Plug.SSL will not, and the
    # endpoint then fails to start.
    assert {:ok, options} =
             env
             |> transport_options()
             |> Keyword.delete(:verify_fun)
             |> Plug.SSL.configure()

    assert {:ok, socket} = :ssl.listen(0, options),
           "Plug.SSL accepted the options, and :ssl then refused them"

    :ssl.close(socket)
  end

  test "seeds that file from DEVICE_SSL_*, and only when it has none", %{env: env} do
    File.write!(env["DEVICE_SSL_KEYFILE"], "KEY\n")
    File.write!(env["DEVICE_SSL_CERTFILE"], "CHAIN\n")
    env = %{env | "DEVICE_TLS_FROM_CLUSTER" => "true"}

    runtime_config(env)
    assert File.read!(env["DEVICE_TLS_PEMFILE"]) == "KEY\n\nCHAIN\n"
    assert Bitwise.band(File.stat!(env["DEVICE_TLS_PEMFILE"]).mode, 0o777) == 0o600

    # A renewal the reloader already installed must not be put back.
    File.write!(env["DEVICE_TLS_PEMFILE"], "RENEWED")
    runtime_config(env)
    assert File.read!(env["DEVICE_TLS_PEMFILE"]) == "RENEWED"
  end

  test "needs no keypair at all, waiting for a provider instead", %{env: env} do
    env = %{
      env
      | "DEVICE_TLS_FROM_CLUSTER" => "true",
        "DEVICE_SSL_KEYFILE" => Path.join(env["DEVICE_TLS_PEMFILE"], "../missing-key.pem"),
        "DEVICE_SSL_CERTFILE" => Path.join(env["DEVICE_TLS_PEMFILE"], "../missing.pem")
    }

    assert transport_options(env)[:certfile] == env["DEVICE_TLS_PEMFILE"]
    refute File.exists?(env["DEVICE_TLS_PEMFILE"])
  end

  test "still refuses to boot with no keypair and no provider", %{env: env} do
    env = %{env | "DEVICE_SSL_KEYFILE" => Path.join(env["DEVICE_TLS_PEMFILE"], "../missing-key.pem")}

    assert_raise RuntimeError, ~r/Could not find keyfile/, fn -> runtime_config(env) end
  end

  defp app_config(env), do: runtime_config(env)[:nerves_hub]

  defp transport_options(env) do
    app_config(env)[NervesHubWeb.DeviceEndpoint][:https][:thousand_island_options][:transport_options]
  end

  defp runtime_config(env) do
    with_env(env, fn -> Config.Reader.read!("config/runtime.exs", env: :prod) end)
  end

  # Sets each variable, or unsets it for `nil`, and puts every one back after.
  defp with_env(env, fun) do
    previous = Map.new(env, fn {name, _value} -> {name, System.get_env(name)} end)

    try do
      Enum.each(env, &put_env/1)
      fun.()
    after
      Enum.each(previous, &put_env/1)
    end
  end

  defp put_env({name, nil}), do: System.delete_env(name)
  defp put_env({name, value}), do: System.put_env(name, value)
end
