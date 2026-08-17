defmodule NervesHubWeb.API.ExternalIdentityJSON do
  @moduledoc false

  alias NervesHub.Devices.ExternalIdentity

  def index(%{external_identities: external_identities}) do
    %{data: for(identity <- external_identities, do: external_identity(identity))}
  end

  def show(%{external_identity: external_identity}) do
    %{data: external_identity(external_identity)}
  end

  @doc """
  The fields common to every view of an identity.

  Public so `NervesHubWeb.API.IrohEndpointJSON` can render the same shape and
  add an owner to it — the two endpoints show the same rows and should not
  disagree about what one looks like.
  """
  def external_identity(%ExternalIdentity{} = identity) do
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
