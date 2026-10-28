defmodule NervesHub.DeviceTLS.ClusterTest do
  @moduledoc """
  Taking the keypair from a TLS provider in the cluster, and installing it.

  `Provider` below stands in for a TLS provider, speaking only the
  contract in `NervesHub.DeviceTLS.Cluster`. Both ends run on this
  one node here; across nodes the only difference is that `:pg` carries the
  calls over distribution.
  """

  # The :pg scope and the reloader are registered by name.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias NervesHub.DeviceTLS
  alias NervesHub.DeviceTLS.Cluster
  alias NervesHub.DeviceTLS.Reloader
  alias X509.Certificate.Extension

  @moduletag :tmp_dir

  @host "devices.example.test"

  defmodule Provider do
    @moduledoc false
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @doc "Hands out `pair` from now on, and tells every consumer."
    def provide(provider, pair), do: GenServer.call(provider, {:provide, pair})

    @impl GenServer
    def init(opts) do
      :ok = :pg.join(:nerves_hub_device_tls, :providers, self())
      {:ok, %{pair: Keyword.get(opts, :pair), versions: Keyword.get(opts, :versions, [1])}}
    end

    @impl GenServer
    def handle_call({:provide, pair}, _from, state) do
      for pid <- :pg.get_members(:nerves_hub_device_tls, :consumers) do
        send(pid, {:nerves_hub_device_tls, 1, :changed, pair.sha1})
      end

      {:reply, :ok, %{state | pair: pair}}
    end

    def handle_call({:nerves_hub_device_tls, version, :fetch, installed}, _from, state) do
      reply =
        cond do
          version not in state.versions -> {:error, {:unsupported_version, state.versions}}
          state.pair == nil -> {:error, "nothing yet"}
          state.pair.sha1 == installed -> :unchanged
          true -> {:ok, Map.take(state.pair, [:key_pem, :chain_pem])}
        end

      {:reply, reply, state}
    end
  end

  setup %{tmp_dir: dir} do
    start_supervised!(Cluster)

    root_key = X509.PrivateKey.new_ec(:secp256r1)
    root = X509.Certificate.self_signed(root_key, "/CN=Test Root", template: :root_ca)

    %{issue: fn -> issue(root, root_key) end, certfile: Path.join(dir, "device_tls.pem")}
  end

  defp issue(root, root_key) do
    key = X509.PrivateKey.new_ec(:secp256r1)

    cert =
      key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("/CN=#{@host}", root, root_key,
        extensions: [subject_alt_name: Extension.subject_alt_name([@host])]
      )

    %{
      key_pem: X509.PrivateKey.to_pem(key),
      chain_pem: X509.Certificate.to_pem(cert) <> X509.Certificate.to_pem(root),
      sha1: :crypto.hash(:sha, X509.Certificate.to_der(cert)) |> Base.encode16(case: :lower)
    }
  end

  defp start_provider(opts \\ []), do: start_supervised!({Provider, opts})

  defp start_reloader(certfile, opts \\ []) do
    start_supervised(
      {Reloader,
       Keyword.merge(
         [
           source: {Cluster, []},
           certfile: certfile,
           host: @host,
           interval: to_timeout(hour: 1),
           boot_timeout: 5_000
         ],
         opts
       )}
    )
  end

  defp eventually(fun, attempts \\ 100) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(20) && eventually(fun, attempts - 1)
    end
  end

  test "a node with no keypair takes the provider's before it starts", context do
    pair = context.issue.()
    :ok = Provider.provide(start_provider(), pair)

    assert {:ok, _} = start_reloader(context.certfile)

    assert DeviceTLS.installed_sha1(context.certfile) == pair.sha1, """
    The reloader started without installing anything, so the device endpoint
    would start listening with no certificate.
    """
  end

  test "a node waits for the provider's first keypair, within the boot timeout", context do
    provider = start_provider()
    pair = context.issue.()

    # Only after the reloader has started waiting.
    spawn(fn ->
      Process.sleep(200)
      Provider.provide(provider, pair)
    end)

    capture_log(fn -> assert {:ok, _} = start_reloader(context.certfile) end)
    assert DeviceTLS.installed_sha1(context.certfile) == pair.sha1
  end

  test "a node with no keypair and no provider fails to start", context do
    log =
      capture_log(fn ->
        assert {:error, _} = start_reloader(context.certfile, boot_timeout: 0)
      end)

    assert log =~ "no TLS provider is in the cluster"
    refute File.exists?(context.certfile)
  end

  test "a renewal reaches the node when the provider says so, not at the next interval",
       context do
    provider = start_provider()
    :ok = Provider.provide(provider, context.issue.())
    {:ok, _} = start_reloader(context.certfile)

    renewed = context.issue.()

    capture_log(fn ->
      :ok = Provider.provide(provider, renewed)

      assert eventually(fn -> DeviceTLS.installed_sha1(context.certfile) == renewed.sha1 end), """
      The renewal was not installed. The interval is an hour, so only the
      provider's :changed message could have done it.
      """
    end)
  end

  test "a failed fetch is retried within seconds, not at the next interval", context do
    seed = context.issue.()
    :ok = DeviceTLS.install(context.certfile, seed.key_pem, seed.chain_pem)

    # As a node boots: the listener starts on its seed, and the first fetch
    # finds no provider because the node has not joined the cluster yet.
    log =
      capture_log(fn ->
        {:ok, _} = start_reloader(context.certfile, retry_after: 50)
        Process.sleep(100)

        # A provider that was already there, so it sends no :changed.
        renewed = context.issue.()
        start_provider(pair: renewed)

        assert eventually(fn -> DeviceTLS.installed_sha1(context.certfile) == renewed.sha1 end), """
        The renewal was not installed. The interval is an hour and the provider
        sent no :changed, so only a retry of the failed fetch could have done it.
        """
      end)

    assert log =~ "no TLS provider is in the cluster"
  end

  test "asks for nothing it already has", context do
    pair = context.issue.()
    :ok = Provider.provide(start_provider(), pair)
    {:ok, _} = start_reloader(context.certfile)

    assert Reloader.poll() == :unchanged
  end

  test "a keypair the provider hands out is still checked here", context do
    good = context.issue.()
    provider = start_provider()
    :ok = Provider.provide(provider, good)
    {:ok, _} = start_reloader(context.certfile)

    # The new chain with the old key: what a half-finished write would look like.
    broken = %{context.issue.() | key_pem: good.key_pem}

    log =
      capture_log(fn ->
        :ok = Provider.provide(provider, broken)
        assert {:error, _} = Reloader.poll()
      end)

    assert log =~ "the private key does not match the certificate"
    assert DeviceTLS.installed_sha1(context.certfile) == good.sha1
  end

  test "a provider speaking another version is refused, by name", context do
    :ok = Provider.provide(start_provider(versions: [2]), context.issue.())

    log =
      capture_log(fn ->
        assert {:error, _} = start_reloader(context.certfile, boot_timeout: 0)
      end)

    assert log =~ "speaks contract versions [2], and this node speaks 1"
  end

  test "ignores another version's nudge" do
    refute Cluster.changed?({:nerves_hub_device_tls, 2, :changed, "abc"})
    assert Cluster.changed?({:nerves_hub_device_tls, 1, :changed, "abc"})
  end
end
