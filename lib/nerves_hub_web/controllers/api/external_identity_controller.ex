defmodule NervesHubWeb.API.ExternalIdentityController do
  @moduledoc """
  What a device holds on networks NervesHub does not run.

  Read-only. A device reports its own identities over its own connection, and
  that is the only way one becomes device-owned — writing one here would be
  recording a claim nobody proved. Register unproven keys against the
  organization instead, with `NervesHubWeb.API.IrohEndpointController`.
  """

  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Devices.ExternalIdentities
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.ErrorSchemas
  alias NervesHubWeb.API.Schemas.ExternalIdentitySchemas

  security([%{"bearer_auth" => []}])
  tags(["External Identities"])

  @auth_error_responses SchemaHelpers.auth_error_responses()

  plug(:validate_role, [org: :view] when action in [:index])

  operation(:index,
    summary: "List the External Identities a Device holds",
    description: """
    The keys this device has reported holding on other networks — an iroh
    endpoint id, a NetBird, Tailscale or WireGuard public key.

    `service` is the protocol. `instance` names which endpoint of it, for a
    device running more than one — an iroh console and an iroh application, say.
    Anything running a single endpoint of a service uses `default`.
    """,
    parameters: [
      org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
      product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"],
      identifier: [in: :path, description: "Device Identifier", type: :string, example: "example_device"],
      service: [
        in: :query,
        description: "Only identities for this protocol",
        type: :string,
        required: false,
        example: "iroh"
      ],
      instance: [
        in: :query,
        description: "Only this endpoint of the protocol",
        type: :string,
        required: false,
        example: "default"
      ]
    ],
    responses:
      [
        ok:
          {"External Identity list response", "application/json", ExternalIdentitySchemas.ExternalIdentityListResponse},
        unprocessable_entity: {"Unknown service", "application/json", ErrorSchemas.ChangesetErrorResponse}
      ] ++ @auth_error_responses
  )

  def index(%{assigns: %{device: device}} = conn, params) do
    with {:ok, service} <- filter_service(params["service"]) do
      identities =
        ExternalIdentities.list_for_device(device.id,
          service: service,
          instance: filter_instance(params["instance"])
        )

      render(conn, :index, external_identities: identities)
    end
  end

  # An unknown service is refused rather than ignored. Ignoring it would answer
  # a typo with every identity the device has, which reads as a device holding
  # keys on a network it has never touched.
  defp filter_service(nil), do: {:ok, nil}
  defp filter_service(""), do: {:ok, nil}

  defp filter_service(service) do
    case ExternalIdentities.cast_service(service) do
      {:ok, service} -> {:ok, service}
      :error -> {:error, :unsupported_service}
    end
  end

  defp filter_instance(instance) when is_binary(instance) do
    case String.trim(instance) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp filter_instance(_instance), do: nil
end
