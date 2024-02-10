defmodule NervesHubWeb.DeviceAdapter do
  @moduledoc """
  Port of Phoenix.Endpoint.Cowboy2Adapter to support device sockets with mTLS

  All functionality is dependent on Phoenix.Endpoint.Cowboy2Adapter and
  this module only adjusts the generated spec for DeviceEndpoint to inject
  `DeviceSSLTransport` for support rate limiting at the socket level. This
  feature is an optimization to keep SSL overhead low when we know we are
  actively preventing connections as well as preventing unnecessary database
  work in NervesHub.SSL.

  If this looks hacky, it's because it is ;) - We may be able to remove this
  in the future if Plug.Cowboy or Phoenix.Endpoint.Cowboy2Adapter support a
  way to specific an alternate module that implements `:ranch_transport` behavior

  May potentially go away pending the results of
  https://github.com/elixir-plug/plug_cowboy/issues/96
  """

  alias NervesHub.DeviceSSLTransport
  alias NervesHubWeb.DeviceEndpoint
  alias Phoenix.Endpoint.Cowboy2Adapter

  @doc false
  def child_specs(endpoint, config) do
    Cowboy2Adapter.child_specs(endpoint, config)
    |> Enum.map(fn
      %{start: {mod, fun, [:https, DeviceEndpoint, {rm, rf, args}]}} = spec ->
        args =
          Enum.map(args, fn
            # replace the default SSL ranch_transport with ours
            :ranch_ssl -> DeviceSSLTransport
            arg -> arg
          end)

        start_spec = {mod, fun, [:https, DeviceEndpoint, {rm, rf, args}]}
        %{spec | start: start_spec}

      child_spec ->
        child_spec
    end)
  end

  defdelegate server_info(endpoint, scheme), to: Cowboy2Adapter
end
