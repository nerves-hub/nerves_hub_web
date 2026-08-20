defmodule NervesHubWeb.API.IrohEndpointJSON do
  @moduledoc false

  alias NervesHub.Devices.ExternalIdentity
  alias NervesHubWeb.API.ExternalIdentityJSON

  def index(%{iroh_endpoints: iroh_endpoints}) do
    %{data: for(endpoint <- iroh_endpoints, do: iroh_endpoint(endpoint))}
  end

  def show(%{iroh_endpoint: iroh_endpoint}) do
    %{data: iroh_endpoint(iroh_endpoint)}
  end

  defp iroh_endpoint(%ExternalIdentity{} = endpoint) do
    endpoint
    |> ExternalIdentityJSON.external_identity()
    |> Map.put(:owner, owner(endpoint))
  end

  # An organization's list is mostly a question of whose each key is, so the
  # owner is spelled out rather than left as an id to look up. `type` is what a
  # caller should branch on; the rest is nil for the kinds that do not have it.
  defp owner(%ExternalIdentity{device: %{identifier: identifier}}) do
    %{type: "device", device_identifier: identifier, user_name: nil, user_email: nil}
  end

  defp owner(%ExternalIdentity{org_user: %{user: %{name: name, email: email}}}) do
    %{type: "user", device_identifier: nil, user_name: name, user_email: email}
  end

  defp owner(%ExternalIdentity{}) do
    %{type: "none", device_identifier: nil, user_name: nil, user_email: nil}
  end
end
