defmodule NervesHub.DeviceTLS.Reloader do
  @moduledoc """
  Keeps the device endpoint's certificate current without a restart.

  Asks a `NervesHub.DeviceTLS.Source` for the keypair every
  `:interval`, and installs anything new with `NervesHub.DeviceTLS`.
  New handshakes get the new certificate; connected devices keep the one they
  negotiated until they next reconnect.

  Started before the device endpoint. If `:certfile` already holds a keypair --
  seeded from `DEVICE_SSL_KEY` and `DEVICE_SSL_CERT` -- the listener starts on
  that and the first fetch happens straight after. If it does not, the listener
  waits for the first keypair, retrying every second for up to `:boot_timeout`
  -- a TLS provider is only reachable once this node has joined the cluster --
  and the boot fails if none arrives: a listener with no certificate would
  accept connections and fail every one.

  Every node polls on its own. There is nothing to coordinate: each one
  installs the same certificate, a few minutes apart at most. A message the
  source recognises with its `changed?/1` -- a provider saying it has a new
  one -- fetches straight away rather than at the next interval.

  A fetch or check that fails leaves the installed keypair alone, and is tried
  again at the next interval. Only a keypair that passes every check is ever
  installed.
  """

  use GenServer

  alias NervesHub.DeviceTLS

  require Logger

  @doc """
  Options:

    * `:source` -- `{module, options}` for a `NervesHub.DeviceTLS.Source`
    * `:certfile` -- the file the listener reads its key and chain from
    * `:host` -- the name the certificate has to cover, or `nil` not to check
    * `:interval` -- milliseconds between fetches
    * `:boot_timeout` -- milliseconds to wait for the first keypair, when
      `:certfile` has none
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Fetches now rather than at the next interval. Returns what happened."
  def poll(server \\ __MODULE__), do: GenServer.call(server, :poll, 60_000)

  @impl GenServer
  def init(opts) do
    {module, source_opts} = Keyword.fetch!(opts, :source)
    {:ok, source_state} = module.init(source_opts)

    state = %{
      source: module,
      source_state: source_state,
      certfile: Keyword.fetch!(opts, :certfile),
      host: Keyword.get(opts, :host),
      interval: Keyword.fetch!(opts, :interval),
      timer: nil
    }

    if DeviceTLS.installed_sha1(state.certfile) do
      {:ok, state, {:continue, :poll}}
    else
      deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :boot_timeout, 0)
      first_install(state, deadline)
    end
  end

  defp first_install(state, deadline) do
    case refresh(state) do
      {{:installed, _sha1}, state} ->
        {:ok, schedule(state)}

      {result, state} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(1_000)
          first_install(state, deadline)
        else
          {:stop, "no certificate for the device endpoint: #{inspect(result)}"}
        end
    end
  end

  @impl GenServer
  def handle_continue(:poll, state) do
    {_result, state} = refresh(state)
    {:noreply, schedule(state)}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    {_result, state} = refresh(state)
    {:noreply, schedule(state)}
  end

  def handle_info(message, state) do
    if function_exported?(state.source, :changed?, 1) and state.source.changed?(message) do
      handle_info(:poll, state)
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call(:poll, _from, state) do
    {result, state} = refresh(state)
    {:reply, result, schedule(state)}
  end

  defp refresh(state) do
    installed = DeviceTLS.installed_sha1(state.certfile)

    case state.source.fetch(installed, state.source_state) do
      {:unchanged, source_state} ->
        {:unchanged, %{state | source_state: source_state}}

      {:error, reason, source_state} ->
        Logger.error("Could not fetch the device endpoint certificate: #{reason}")
        {{:error, reason}, %{state | source_state: source_state}}

      {:ok, %{key_pem: key_pem, chain_pem: chain_pem}, source_state} ->
        state = %{state | source_state: source_state}
        result = install(state, key_pem, chain_pem, installed)

        report =
          case result do
            {:installed, _sha1} -> :ok
            {:error, reason} -> {:error, format_reason(reason)}
          end

        {result, %{state | source_state: state.source.installed(report, state.source_state)}}
    end
  end

  defp install(state, key_pem, chain_pem, installed) do
    with {:ok, summary} <- DeviceTLS.check(key_pem, chain_pem, state.host),
         :ok <- install_unless_current(state.certfile, key_pem, chain_pem, summary, installed) do
      {:installed, summary.sha1}
    else
      {:error, reason} = error ->
        Logger.error("Refused a certificate for the device endpoint: #{format_reason(reason)}")
        error
    end
  end

  defp install_unless_current(_certfile, _key_pem, _chain_pem, %{sha1: sha1}, sha1), do: :ok

  defp install_unless_current(certfile, key_pem, chain_pem, summary, _installed) do
    with :ok <- DeviceTLS.install(certfile, key_pem, chain_pem) do
      Logger.info(
        "Installed a new device endpoint certificate: #{summary.subject}, " <>
          "sha1 #{summary.sha1}, expires #{summary.not_after}"
      )
    end
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  # Spread over a tenth of the interval, so a fleet of nodes started together
  # does not keep fetching together.
  defp schedule(state) do
    _ = if state.timer, do: Process.cancel_timer(state.timer)
    jitter = :rand.uniform(max(div(state.interval, 10), 1))
    %{state | timer: Process.send_after(self(), :poll, state.interval + jitter)}
  end
end
