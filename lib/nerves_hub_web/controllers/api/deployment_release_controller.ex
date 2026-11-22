defmodule NervesHubWeb.API.DeploymentReleaseController do
  @moduledoc """
  A deployment group's releases: listing them, making a new one, and changing
  what can still change on one once it's made.

  A release is found by its `number` within its group, which counts up from 1.
  """

  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias Ecto.Changeset
  alias NervesHub.Accounts.Scope
  alias NervesHub.Archives
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.DeploymentReleaseSchemas
  alias NervesHubWeb.API.Schemas.ErrorSchemas

  security([%{"bearer_auth" => []}])
  tags(["Deployment Groups"])

  @auth_error_responses SchemaHelpers.auth_error_responses()

  # The same checks as the deployment group page's Releases tab.
  plug(:require_membership when action in [:index, :show])
  plug(:require_every_device)
  plug(:require_permission, :"deployment_group:update" when action in [:create, :update])

  @group_params [
    org_name: [in: :path, description: "Organization Name", type: :string, example: "example_org"],
    product_name: [in: :path, description: "Product Name", type: :string, example: "example_product"],
    name: [in: :path, description: "Deployment Group Name", type: :string, example: "production"]
  ]

  @release_params @group_params ++
                    [
                      number: [
                        in: :path,
                        description: "Release number within the deployment group",
                        type: :integer,
                        example: 3
                      ]
                    ]

  operation(:index,
    summary: "List a Deployment Group's releases, newest first",
    parameters: @group_params,
    responses:
      [
        ok: {"Release list response", "application/json", DeploymentReleaseSchemas.DeploymentReleaseListResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def index(%{assigns: %{current_scope: %{product: product}}} = conn, %{"name" => name}) do
    with {:ok, deployment_group} <- ManagedDeployments.get_deployment_group_by_name(product, name) do
      releases = ManagedDeployments.list_deployment_releases(deployment_group)
      render(conn, :index, releases: releases, deployment_group: deployment_group)
    end
  end

  operation(:create,
    summary: "Create a release, which becomes the Deployment Group's current release",
    description: """
    The new release does not take the previous release's archive: leave `archive` out
    and it has none.

    Refused if the current release already has the same firmware and archive. Mark a
    release required, or change its connecting code, with PATCH instead.
    """,
    parameters: @group_params,
    request_body: {
      "Release creation request body",
      "application/json",
      DeploymentReleaseSchemas.DeploymentReleaseCreationRequest,
      required: true
    },
    responses:
      [
        created: {"Release response", "application/json", DeploymentReleaseSchemas.DeploymentReleaseResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse},
        unprocessable_entity: {"Unprocessable Entity", "application/json", ErrorSchemas.ChangesetErrorResponse}
      ] ++ @auth_error_responses
  )

  def create(%{assigns: %{current_scope: %{org: org, product: product} = scope}} = conn, %{"name" => name} = params) do
    with {:ok, deployment_group} <- ManagedDeployments.get_deployment_group_by_name(product, name),
         {:ok, firmware, archive} <- resolve_firmware_and_archive(product, params),
         {:ok, {release, deployment_group}} <-
           ManagedDeployments.create_deployment_release(
             deployment_group,
             firmware,
             archive,
             Scope.actor(scope),
             params
           ),
         {:ok, release} <- ManagedDeployments.get_deployment_release_by_number(deployment_group, release.number) do
      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        Routes.api_deployment_release_path(conn, :show, org.name, product.name, deployment_group.name, release.number)
      )
      |> render(:show, release: release, deployment_group: deployment_group)
    end
  end

  operation(:show,
    summary: "Show one of a Deployment Group's releases",
    parameters: @release_params,
    responses:
      [
        ok: {"Release response", "application/json", DeploymentReleaseSchemas.DeploymentReleaseResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def show(%{assigns: %{current_scope: %{product: product}}} = conn, %{"name" => name, "number" => number}) do
    with {:ok, deployment_group} <- ManagedDeployments.get_deployment_group_by_name(product, name),
         {:ok, release} <- get_release(deployment_group, number) do
      render(conn, :show, release: release, deployment_group: deployment_group)
    end
  end

  operation(:update,
    summary: "Change whether a release is required, or its connecting code",
    description: """
    The firmware, archive, description and notes of a release are fixed once it's made.
    Create a new release to send different firmware.
    """,
    parameters: @release_params,
    request_body: {
      "Release update request body",
      "application/json",
      DeploymentReleaseSchemas.DeploymentReleaseUpdateRequest,
      required: true
    },
    responses:
      [
        ok: {"Release response", "application/json", DeploymentReleaseSchemas.DeploymentReleaseResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse},
        unprocessable_entity: {"Unprocessable Entity", "application/json", ErrorSchemas.ChangesetErrorResponse}
      ] ++ @auth_error_responses
  )

  def update(
        %{assigns: %{current_scope: %{product: product} = scope}} = conn,
        %{"name" => name, "number" => number} = params
      ) do
    with {:ok, deployment_group} <- ManagedDeployments.get_deployment_group_by_name(product, name),
         {:ok, release} <- get_release(deployment_group, number),
         {:ok, release} <-
           ManagedDeployments.update_deployment_release(release, params, Scope.actor(scope)),
         # Marking a release required can change its delta status, which is
         # recorded after the update.
         {:ok, release} <- ManagedDeployments.get_deployment_release_by_number(deployment_group, release.number) do
      render(conn, :show, release: release, deployment_group: deployment_group)
    end
  end

  # A release number is a Postgres `integer`, which can't be given anything
  # bigger to compare with, so a number past it names no release.
  @max_release_number 2_147_483_647

  defp get_release(deployment_group, number) do
    case Integer.parse(number) do
      {number, ""} when number in 1..@max_release_number//1 ->
        ManagedDeployments.get_deployment_release_by_number(deployment_group, number)

      _ ->
        {:error, :not_found}
    end
  end

  # Firmware and archive are named by UUID. One that names nothing in the
  # product is refused, rather than making a release without it. Leaving either
  # out (or sending "") means none, and a release with no firmware is left to
  # the release's own validation to refuse.
  defp resolve_firmware_and_archive(product, params) do
    firmware = resolve(:firmware, params["firmware"], &Firmwares.get_firmware_by_product_and_uuid(product, &1))
    archive = resolve(:archive, params["archive"], &get_archive(product, &1))

    case {firmware, archive} do
      {{:ok, firmware}, {:ok, archive}} ->
        {:ok, firmware, archive}

      _ ->
        changeset =
          Enum.reduce([firmware, archive], Changeset.change(%DeploymentRelease{}), fn
            {:error, field}, changeset -> Changeset.add_error(changeset, field, "does not exist")
            {:ok, _}, changeset -> changeset
          end)

        {:error, %{changeset | action: :insert}}
    end
  end

  defp resolve(_field, uuid, _fetch) when uuid in [nil, ""], do: {:ok, nil}

  defp resolve(field, uuid, fetch) when is_binary(uuid) do
    case fetch.(uuid) do
      {:ok, found} -> {:ok, found}
      _ -> {:error, field}
    end
  end

  defp resolve(field, _uuid, _fetch), do: {:error, field}

  # An archive's UUID is an `Ecto.UUID`, which a query can't be given anything
  # else for. A firmware's is a plain string.
  defp get_archive(product, uuid) do
    with {:ok, uuid} <- Ecto.UUID.cast(uuid), do: Archives.get(product, uuid)
  end
end
