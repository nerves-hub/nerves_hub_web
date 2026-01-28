defmodule NervesHubWeb.Components.DeploymentGroupPage.Releases do
  use NervesHubWeb, :live_component

  alias NervesHub.Archives
  alias NervesHub.AuditLogs
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    archives = Archives.all_by_product(assigns.deployment_group.product)
    firmwares = Firmwares.get_firmwares_for_deployment_group(assigns.deployment_group)

    changeset = DeploymentGroup.update_changeset(assigns.deployment_group, %{})

    socket
    |> assign(assigns)
    |> assign(:archives, archives)
    |> assign(:firmwares, firmwares)
    |> assign(:form, to_form(changeset))
    |> ok()
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="flex flex-col p-6 gap-6">
      <.form id="release-form" for={@form} class="w-full flex flex-col gap-4" phx-change="validate-release" phx-submit="update-release" phx-target={@myself}>
        <div class="w-2/3 flex flex-col bg-zinc-900 border border-zinc-700 rounded">
          <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
            <div class="text-base text-neutral-50 font-medium">Release settings</div>
          </div>

          <div class="flex flex-col p-6 gap-6">
            <div class="w-1/2 flex flex-col gap-6">
              <.input
                field={@form[:firmware_id]}
                type="select"
                options={firmware_dropdown_options(@firmwares)}
                label="Firmware version"
                hint="Firmware listed is the same platform and architecture as the currently selected firmware."
              />
            </div>

            <div class="w-1/2 flex flex-col gap-6">
              <.input
                field={@form[:archive_id]}
                type="select"
                options={archive_dropdown_options(@archives)}
                prompt="Select an Archive"
                label="Additional Archive version"
                hint="Firmware listed is the same platform and architecture as the currently selected firmware."
              />
            </div>

            <div>
              <.button style="secondary" type="submit">
                <.icon name="save" /> Save changes
              </.button>
            </div>
          </div>
        </div>
      </.form>

      <div class="w-full">
        <div class="flex flex-col bg-zinc-900 border border-zinc-700 rounded">
          <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
            <div class="text-base text-neutral-50 font-medium">Release History</div>
          </div>

          <div :if={@releases == []} class="flex flex-col items-center justify-center p-12 gap-4">
            <div class="text-zinc-400">No releases yet</div>
            <div class="text-sm text-zinc-500">
              Release history will appear here when you change the firmware version above.
            </div>
          </div>

          <div :if={@releases != []} class="overflow-x-auto">
            <table class="w-full">
              <thead class="border-b border-zinc-700">
                <tr>
                  <th class="text-left px-4 py-3 text-sm font-medium text-zinc-400">Released</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-zinc-400">Firmware Version</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-zinc-400">UUID</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-zinc-400">Archive</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-zinc-400">Released By</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={release <- @releases} class="border-b border-zinc-800 hover:bg-zinc-800/50">
                  <td class="px-4 py-3 text-sm text-zinc-300">
                    <div class="flex flex-col">
                      <span>{Calendar.strftime(release.inserted_at, "%B %d, %Y")}</span>
                      <span class="text-xs text-zinc-500">{Calendar.strftime(release.inserted_at, "%I:%M %p")} UTC</span>
                    </div>
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-300 font-medium">
                    {release.firmware.version}
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-400 font-mono">
                    {release.firmware.uuid}
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-400">
                    <span :if={release.archive}>
                      {release.archive.version} ({String.slice(release.archive.uuid, 0..7)})
                    </span>
                    <span :if={!release.archive} class="text-zinc-500 italic">
                      None
                    </span>
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-400">
                    <span :if={release.user}>
                      {release.user.name}
                    </span>
                    <span :if={!release.user} class="text-zinc-500 italic">
                      Unknown
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate-release", %{"deployment_group" => params}, socket) do
    changeset =
      socket.assigns.deployment_group
      |> DeploymentGroup.update_changeset(params)

    socket
    |> assign(:form, to_form(changeset, action: :validate))
    |> noreply()
  end

  def handle_event("update-release", %{"deployment_group" => params}, socket) do
    %{
      org_user: org_user,
      user: user,
      deployment_group: deployment_group
    } =
      socket.assigns

    authorized!(:"deployment_group:update", org_user)

    case ManagedDeployments.update_deployment_group(deployment_group, params, user) do
      {:ok, updated} ->
        AuditLogs.audit!(
          user,
          updated,
          "User #{user.name} updated deployment group #{updated.name}"
        )

        releases = ManagedDeployments.list_deployment_releases(updated)
        changeset = DeploymentGroup.update_changeset(updated, %{})

        send(self(), {:flash, :info, "Release settings updated"})

        socket
        |> assign(:deployment_group, updated)
        |> assign(:releases, releases)
        |> assign(:form, to_form(changeset))
        |> noreply()

      {:error, changeset} ->
        socket
        |> put_flash(
          :error,
          "An error occurred while updating the release settings. Please check the form for errors."
        )
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  defp firmware_dropdown_options(firmwares) do
    firmwares
    |> Enum.sort_by(
      fn firmware ->
        case Version.parse(firmware.version) do
          {:ok, version} ->
            version

          :error ->
            %Version{major: 0, minor: 0, patch: 0}
        end
      end,
      {:desc, Version}
    )
    |> Enum.map(&[value: &1.id, key: firmware_display_name(&1)])
  end

  defp archive_dropdown_options(archives) do
    archives
    |> Enum.sort_by(
      fn archive ->
        case Version.parse(archive.version) do
          {:ok, version} ->
            version

          :error ->
            %Version{major: 0, minor: 0, patch: 0}
        end
      end,
      {:desc, Version}
    )
    |> Enum.map(&[value: &1.id, key: archive_display_name(&1)])
  end

  defp archive_display_name(%{} = a) do
    "#{a.version} - #{a.platform} - #{a.architecture} (#{String.slice(a.uuid, 0..7)})"
  end

  defp firmware_display_name(%Firmware{} = f) do
    "#{f.version} - #{f.platform} - #{f.architecture} (#{String.slice(f.uuid, 0..7)})"
  end
end
