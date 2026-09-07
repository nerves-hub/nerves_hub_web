defmodule NervesHubWeb.API.NetworkIdentityJSON do
  @moduledoc false

  alias NervesHub.Devices.NetworkIdentity

  def index(%{network_identities: network_identities}) do
    %{data: for(identity <- network_identities, do: network_identity(identity))}
  end

  def show(%{network_identity: network_identity}) do
    %{data: network_identity(network_identity)}
  end

  @doc """
  The fields common to every view of an identity.

  Public so `NervesHubWeb.API.IrohEndpointJSON` can render the same shape and
  add an owner to it — the two endpoints show the same rows and should not
  disagree about what one looks like.
  """
  def network_identity(%NetworkIdentity{} = identity) do
    %{
      identifier: identity.identifier,
      service: identity.service,
      instance: identity.instance,
      # Whether anything has actually proven this key: `device_reported` means a
      # device did, on its own connection. `operator` means somebody typed it in.
      source: identity.source,
      details: identity.details,
      last_reported_at: identity.last_reported_at,
      inserted_at: identity.inserted_at,
      updated_at: identity.updated_at
    }
  end
end
