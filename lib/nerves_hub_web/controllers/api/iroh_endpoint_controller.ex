defmodule NervesHubWeb.API.IrohEndpointController do
  @moduledoc """
  An organisation's iroh endpoint ids, over the API.

  The same registry the Iroh Endpoints page manages, addressed by the key
  itself rather than by a row id: the key is what a caller has, it is unique
  per service, and an id would mean listing before you could act.

  Fixed to iroh, like the page. `NetworkIdentityController` is the generic view
  of the same table, for reading what a device has reported about itself.
  """

  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Accounts
  alias NervesHub.Devices.NetworkIdentities
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.ErrorSchemas
  alias NervesHubWeb.API.Schemas.IrohEndpointSchemas
  alias OpenApiSpex.Schema

  security([%{"bearer_auth" => []}])
  tags(["Iroh Endpoints"])

  @auth_error_responses SchemaHelpers.auth_error_responses()

  @service :iroh

  plug(:validate_role, [org: :manage] when action in [:create, :delete])
  plug(:validate_role, [org: :view] when action in [:index, :show])

  @org_name_parameter [
    in: :path,
    description: "Organization Name",
    type: :string,
    example: "example_org"
  ]

  @identifier_parameter [
    in: :path,
    description: "The endpoint id — 64 hex characters",
    type: :string,
    example: "c8924b6c9b7a8528b1365ebec4b2e43b6edebef684f8521f12b8caaf6e1b2302"
  ]

  operation(:index,
    summary: "List all Iroh Endpoints for an Organization",
    description: """
    Newest first.

    `search` matches the **start** of an endpoint id, and anywhere within a
    device identifier or a member's name. Prefix rather than substring on the
    key because that is the half a caller has: logs and tables show a key
    truncated, so the beginning is what can be copied out of one.
    """,
    parameters: [
      org_name: @org_name_parameter,
      owner: [
        in: :query,
        description: "Only endpoints held by this kind of owner, matching the `owner.type` in the response",
        type: %Schema{type: :string, enum: ["device", "user", "none"]},
        required: false,
        example: "user"
      ],
      search: [
        in: :query,
        description: "Match the start of an endpoint id, or part of a device identifier or member name",
        type: :string,
        required: false,
        example: "c8924b6c"
      ]
    ],
    responses:
      [
        ok: {"Iroh Endpoints", "application/json", IrohEndpointSchemas.IrohEndpointListResponse},
        unprocessable_entity: {"Unknown owner", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def index(%{assigns: %{current_scope: %{org: org}}} = conn, params) do
    with {:ok, owner} <- filter_owner(params["owner"]) do
      endpoints =
        NetworkIdentities.list_for_org(org.id,
          service: @service,
          owner: owner,
          # Passed through as it arrives. The context trims it, treats a blank
          # one as no filter, and escapes the LIKE wildcards, so a search for
          # "abc_" looks for that rather than matching everything.
          search: params["search"]
        )

      render(conn, :index, iroh_endpoints: endpoints)
    end
  end

  # Named for what `owner.type` renders in the response rather than for the
  # context's own values, so a caller reading "user" back can filter with
  # "user" instead of learning a second vocabulary for the same three things.
  #
  # An unknown one is refused rather than ignored: ignoring it would answer a
  # typo with the whole list, which looks like a filter that found everything.
  defp filter_owner(owner) when owner in [nil, ""], do: {:ok, nil}
  defp filter_owner("device"), do: {:ok, :device}
  defp filter_owner("user"), do: {:ok, :org_user}
  defp filter_owner("none"), do: {:ok, :unowned}
  defp filter_owner(_owner), do: {:error, :unknown_owner}

  operation(:create,
    summary: "Register an Iroh Endpoint for an Organization",
    description: """
    Records an endpoint id nobody has proven yet, which is the point and also
    the risk. A key already registered anywhere is refused, without saying
    where — whether another organization holds one is that organization's
    business.

    A key registered here for a device in this organization is claimed by that
    device the next time it connects and proves it, so registering ahead of
    provisioning needs no cleanup.
    """,
    parameters: [org_name: @org_name_parameter],
    request_body: {
      "Iroh Endpoint registration request body",
      "application/json",
      IrohEndpointSchemas.IrohEndpointCreateRequest,
      required: true
    },
    responses:
      [
        created: {"Iroh Endpoint", "application/json", IrohEndpointSchemas.IrohEndpointShowResponse},
        conflict: {"Already registered", "application/json", ErrorSchemas.ErrorResponse},
        unprocessable_entity: {"Unprocessable Entity", "application/json", ErrorSchemas.ChangesetErrorResponse}
      ] ++ @auth_error_responses
  )

  def create(%{assigns: %{current_scope: %{org: org}}} = conn, params) do
    with {:ok, org_user_id} <- resolve_member(org, params["user_email"]),
         attrs = registration_attrs(params, org_user_id),
         {:ok, registered} <- NetworkIdentities.register(org.id, @service, attrs),
         # Read it back rather than render what register/3 returned. That struct
         # has no owner loaded, so an endpoint just attached to a person would
         # render as belonging to nobody — and create would disagree with show
         # about the same row.
         {:ok, endpoint} <- NetworkIdentities.get_for_org(org.id, @service, registered.identifier) do
      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        Routes.api_iroh_endpoint_path(conn, :show, org.name, endpoint.identifier)
      )
      |> render(:show, iroh_endpoint: endpoint)
    end
  end

  operation(:show,
    summary: "Show an Iroh Endpoint for an Organization",
    parameters: [org_name: @org_name_parameter, identifier: @identifier_parameter],
    responses:
      [
        ok: {"Iroh Endpoint", "application/json", IrohEndpointSchemas.IrohEndpointShowResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def show(%{assigns: %{current_scope: %{org: org}}} = conn, %{"identifier" => identifier}) do
    with {:ok, endpoint} <- NetworkIdentities.get_for_org(org.id, @service, identifier) do
      render(conn, :show, iroh_endpoint: endpoint)
    end
  end

  operation(:delete,
    summary: "Delete an Iroh Endpoint for an Organization",
    description: """
    An endpoint a device reported is removed too, but the device records it
    again the next time it connects — deleting one is not a way to stop a device
    holding a key it holds.
    """,
    parameters: [org_name: @org_name_parameter, identifier: @identifier_parameter],
    responses:
      [
        no_content: "Empty response",
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def delete(%{assigns: %{current_scope: %{org: org}}} = conn, %{"identifier" => identifier}) do
    with {:ok, endpoint} <- NetworkIdentities.get_for_org(org.id, @service, identifier),
         {:ok, _endpoint} <- NetworkIdentities.delete(org.id, endpoint.id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp registration_attrs(params, org_user_id) do
    %{
      "identifier" => params["identifier"],
      "instance" => params["instance"],
      "details" => params["details"],
      "org_user_id" => org_user_id
    }
  end

  # Memberships are addressed by the member's email here, not by `org_user_id`.
  # The organization members API exposes no ids, so one would be a value a
  # caller has no way to look up.
  defp resolve_member(_org, email) when email in [nil, ""], do: {:ok, nil}

  defp resolve_member(org, email) when is_binary(email) do
    with {:ok, user} <- Accounts.get_user_by_email(email),
         {:ok, org_user} <- Accounts.get_org_user(org, user) do
      {:ok, org_user.id}
    else
      # Deliberately the same answer for "no such user" and "not in this
      # organization": the caller may not know either, and this endpoint is not
      # a way to find out which addresses have accounts.
      _other -> {:error, :invalid_member}
    end
  end

  defp resolve_member(_org, _email), do: {:error, :invalid_member}
end
