defmodule NervesHub.DeviceTLS.Cluster do
  @moduledoc """
  The device endpoint's keypair, from a TLS provider somewhere in the cluster.

  A TLS provider is a separate application that joins the cluster and knows
  where the certificate comes from -- one could run CertKit's agent, another
  speak ACME or read Vault. This node does not need
  to know which. It asks for a key and a chain, and checks both itself before
  installing anything, so a provider only has to relay them.

  ## The contract

  Both ends join the `:pg` scope `:nerves_hub_device_tls`, which each starts on
  its own nodes:

    * providers join the group `:providers`, and answer
      `{:nerves_hub_device_tls, 1, :fetch, installed_sha1}` -- `installed_sha1`
      the lowercase hex SHA-1 of the leaf this node holds, or `nil` -- with
      `{:ok, %{key_pem: binary, chain_pem: binary}}`, `:unchanged` or
      `{:error, reason}`
    * each node's reloader joins `:consumers`, and is sent
      `{:nerves_hub_device_tls, 1, :changed, sha1}` when a provider has
      something new

  The `1` is the contract's version. A provider that does not speak this
  version replies `{:error, {:unsupported_version, versions}}`, and a node that
  hears a version it does not speak ignores it, so a mismatched pair fails
  loudly at the next fetch rather than quietly. Change the shape of a message,
  and the version goes up on both sides.

  `:changed` is a nudge, not the keypair: the reloader fetches on hearing it,
  as it does on its own interval. A node that was not listening -- booting, or
  on the wrong side of a netsplit -- catches up at its next interval.

  The keypair crosses Erlang distribution. That is no wider than the cluster's
  trust already is: anything holding the cookie can run code on a device node
  and read the file it lands in.
  """

  @behaviour NervesHub.DeviceTLS.Source

  alias NervesHub.DeviceTLS.Source

  @scope :nerves_hub_device_tls
  @version 1
  @timeout 10_000

  @doc "Starts the contract's `:pg` scope on this node."
  def child_spec(_opts), do: %{id: @scope, start: {:pg, :start_link, [@scope]}}

  @impl Source
  def init(_opts) do
    # init runs in the reloader, so this is the reloader joining.
    :ok = :pg.join(@scope, :consumers, self())
    {:ok, nil}
  end

  @impl Source
  def fetch(installed_sha1, state) do
    case :pg.get_members(@scope, :providers) do
      [] ->
        {:error, "no TLS provider is in the cluster", state}

      providers ->
        providers
        |> Enum.random()
        |> call({:nerves_hub_device_tls, @version, :fetch, installed_sha1})
        |> from_reply(state)
    end
  end

  defp from_reply({:ok, %{key_pem: key_pem, chain_pem: chain_pem}}, state)
       when is_binary(key_pem) and is_binary(chain_pem) do
    {:ok, %{key_pem: key_pem, chain_pem: chain_pem}, state}
  end

  # Not inspected: one of the two may well be the private key.
  defp from_reply({:ok, %{key_pem: _, chain_pem: _}}, state) do
    {:error, "the TLS provider replied with a key or chain that is not a binary", state}
  end

  defp from_reply(:unchanged, state), do: {:unchanged, state}

  defp from_reply({:error, {:unsupported_version, versions}}, state) do
    {:error, "the TLS provider speaks contract versions #{inspect(versions)}, and this node speaks #{@version}", state}
  end

  defp from_reply({:error, reason}, state) do
    {:error, "the TLS provider has none to give: #{format(reason)}", state}
  end

  defp from_reply(other, state), do: {:error, "the TLS provider replied with #{inspect(other)}", state}

  @impl Source
  def installed(_result, state), do: state

  # A provider's nudge, in a version this node speaks; other versions' nudges
  # are ignored.
  @impl Source
  def changed?({:nerves_hub_device_tls, @version, :changed, _sha1}), do: true
  def changed?(_message), do: false

  defp call(provider, message) do
    GenServer.call(provider, message, @timeout)
  catch
    :exit, reason -> {:error, "could not reach it: #{inspect(reason)}"}
  end

  defp format(reason) when is_binary(reason), do: reason
  defp format(reason), do: inspect(reason)
end
