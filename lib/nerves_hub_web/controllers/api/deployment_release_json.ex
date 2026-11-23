defmodule NervesHubWeb.API.DeploymentReleaseJSON do
  @moduledoc false

  alias NervesHub.Accounts.User
  alias NervesHub.ManagedDeployments
  alias NervesHub.Products.ApiKey

  def index(%{releases: releases, deployment_group: deployment_group}) do
    %{data: for(release <- releases, do: release(release, deployment_group))}
  end

  def show(%{release: release, deployment_group: deployment_group}) do
    %{data: release(release, deployment_group)}
  end

  defp release(release, deployment_group) do
    %{
      number: release.number,
      firmware: firmware(release.firmware),
      archive_uuid: get_in(release.archive.uuid),
      required: release.required,
      description: release.description,
      notes: release.notes,
      connecting_code: release.connecting_code,
      connecting_code_mode: release.connecting_code_mode,
      delta_status: release.delta_status,
      is_current: release.id == deployment_group.current_deployment_release_id,
      created_by: author(ManagedDeployments.release_author(release)),
      inserted_at: release.inserted_at,
      updated_at: release.updated_at
    }
  end

  defp firmware(firmware) do
    %{
      version: firmware.version,
      architecture: firmware.architecture,
      platform: firmware.platform,
      uuid: firmware.uuid
    }
  end

  defp author(%User{name: name, email: email}), do: %{type: "user", name: name, email: email}
  defp author(%ApiKey{name: name}), do: %{type: "api_key", name: name}
  defp author(nil), do: nil
end
