defmodule NervesHubWeb.Components.DeploymentGroupPage.Releases do
  use NervesHubWeb, :live_component

  alias NervesHub.Archives
  alias NervesHub.AuditLogs
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHubWeb.Components.Utils
  alias NervesHubWeb.CoreComponents

  @impl Phoenix.LiveComponent
  def update(%{event: {:firmware_created, firmware}}, socket) do
    firmwares = Firmwares.get_firmwares_for_deployment_group(socket.assigns.deployment_group)

    socket
    |> assign(:firmwares, firmwares)
    |> send_flash(
      :notice,
      "New firmware #{firmware.version} (#{String.slice(firmware.uuid, 0..7)}) is available for selection"
    )
    |> ok()
  end

  def update(%{event: {:firmware_deleted, firmware}}, socket) do
    firmwares = Firmwares.get_firmwares_for_deployment_group(socket.assigns.deployment_group)

    socket
    |> assign(:firmwares, firmwares)
    |> send_flash(
      :notice,
      "Firmware list has been updated. Firmware #{firmware.version} (#{String.slice(firmware.uuid, 0..7)}) has been deleted by another user."
    )
    |> ok()
  end

  def update(assigns, socket) do
    archives = Archives.all_by_product(assigns.deployment_group.product)
    firmwares = Firmwares.get_firmwares_for_deployment_group(assigns.deployment_group)

    changeset = DeploymentRelease.new_changeset(assigns.deployment_group)

    releases = ManagedDeployments.list_deployment_releases(assigns.deployment_group)

    socket
    |> assign(assigns)
    |> assign(:archives, archives)
    |> assign(:firmwares, firmwares)
    |> assign(:form, to_form(changeset))
    |> assign(:releases, releases)
    |> assign(:show_rollout_options, false)
    |> ok()
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-6 p-6">
      <div class="w-full">
        <div class="bg-base-900 border-base-700 flex flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base font-medium text-neutral-50">Release History</div>

            <.button style="secondary" type="submit" phx-click={CoreComponents.show_modal("new-release")}>
              <svg class="size-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="none">
                <path
                  d="M4.1665 10.0001H9.99984M15.8332 10.0001H9.99984M9.99984 10.0001V4.16675M9.99984 10.0001V15.8334"
                  stroke="#A1A1AA"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
              Create new release
            </.button>
          </div>

          <div :if={@releases == []} class="flex flex-col items-center justify-center gap-4 p-12">
            <div class="text-base-400">No releases have been created.</div>
            <div class="text-base-500 text-sm">
              Release history will appear here when you change the firmware version above.
            </div>
          </div>

          <div :if={@releases != []} class="overflow-x-auto">
            <div class="w-full">
              <div :for={release <- @releases} class="border-base-800 hover:bg-base-800/50 border-b">
                <div class="flex w-full">
                  <div class="text-base-300 w-44 px-4 py-3 text-sm">
                    <div class="flex flex-col">
                      <span>{Calendar.strftime(release.inserted_at, "%B %d, %Y")}</span>
                      <span class="text-base-500 text-xs">{Calendar.strftime(release.inserted_at, "%I:%M %p")} UTC</span>
                    </div>
                  </div>

                  <div class="flex grow flex-col gap-2 px-4 py-3 text-sm">
                    <div class="flex">
                      <span :if={release.description} class="text-base-300 grow font-semibold">
                        {release.description}
                      </span>
                      <span :if={!release.description} class="text-base-400 grow font-medium">
                        No description
                      </span>

                      <.link :if={release.notes} phx-click={CoreComponents.show_modal("release-notes-#{release.id}")} class="text-base-300 font-medium underline decoration-dashed hover:decoration-solid">
                        Show notes
                      </.link>
                      <CoreComponents.modal
                        id={"release-notes-#{release.id}"}
                        on_cancel={Phoenix.LiveView.JS.patch(~p"/org/#{@current_scope.org}/#{@current_scope.product}/deployment_groups/#{@deployment_group}/releases")}
                      >
                        <div class="p-4">
                          <h2 class="text-base-300 pb-5 text-lg font-semibold">Release notes</h2>
                          <div class="bg-base-800/50 p-5 whitespace-break-spaces">{release.notes}</div>
                        </div>
                      </CoreComponents.modal>
                    </div>

                    <div class="flex gap-4">
                      <div>
                        <span class="text-base-400">Firmware:</span>
                        <span class="text-base-300 font-medium">
                          {release.firmware.version}
                        </span>
                        <span class="text-base-300 font-mono">
                          <.link class="underline decoration-dashed hover:decoration-solid" navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/firmware/#{release.firmware.uuid}"}>
                            ({String.slice(release.firmware.uuid, 0..7)})
                          </.link>
                        </span>
                      </div>

                      <div class="text-sm">
                        <span class="text-base-400">Archive:</span>
                        <span :if={release.archive} class="text-base-300 font-medium">
                          {release.archive.version}
                        </span>
                        <span :if={release.archive} class="text-base-400 font-mono">
                          <.link class="underline decoration-dashed hover:decoration-solid" navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/archives/#{release.archive.uuid}"}>
                            ({String.slice(release.archive.uuid, 0..7)})
                          </.link>
                        </span>
                        <span :if={!release.archive} class="text-base-400 font-medium">
                          None
                        </span>
                      </div>
                    </div>
                  </div>

                  <div class="text-base-400 flex w-54 flex-col gap-0.5 px-8 py-3 text-sm">
                    <span>Released by:</span>
                    <span :if={release.created_by}>
                      {release.created_by.name}
                    </span>
                    <span :if={!release.created_by} class="text-base-500 italic">
                      Unknown
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
      <CoreComponents.modal id="new-release" on_cancel={Phoenix.LiveView.JS.patch(~p"/org/#{@current_scope.org}/#{@current_scope.product}/deployment_groups/#{@deployment_group}/releases")}>
        <.form :let={f} id="release-form" for={@form} phx-change="validate-release" phx-submit="update-release" phx-target={@myself}>
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base font-medium text-neutral-50">Release settings</div>
          </div>

          <div class="flex flex-col gap-6 p-4">
            <div class="flex w-1/2 flex-col gap-6">
              <.input
                field={f[:description]}
                type="text"
                label="Description"
                hint="Optional release description, max 100 characters."
              />
            </div>

            <div class="flex w-1/2 flex-col gap-6">
              <.input
                field={f[:firmware]}
                value={firmware_or_archive_value(f[:firmware], NervesHub.Firmwares.Firmware)}
                type="select"
                options={firmware_dropdown_options(@firmwares)}
                label="Firmware version"
                prompt="Select a Firmware version"
                hint="Firmware listed is the same platform and architecture as the currently selected firmware."
              />
            </div>

            <div class="flex w-1/2 flex-col gap-6">
              <.input
                field={f[:archive]}
                value={firmware_or_archive_value(f[:archive], NervesHub.Archives.Archive)}
                type="select"
                options={archive_dropdown_options(@archives)}
                prompt="Select an Archive"
                label="Additional Archive version"
              />
            </div>

            <div class="flex w-1/2 flex-col gap-6">
              <.input
                field={f[:notes]}
                type="textarea"
                label="Notes"
                hint="Optional release notes which describe or explain whats included in the update, max 500 characters."
              />
            </div>

            <.rollout_options show_rollout_options={@show_rollout_options} myself={@myself} />

            <div>
              <.button style="secondary" type="submit">
                <.icon name="save" /> Create release
              </.button>
            </div>
          </div>
        </.form>
      </CoreComponents.modal>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle-rollout-options", _params, socket) do
    socket
    |> assign(:show_rollout_options, !socket.assigns.show_rollout_options)
    |> noreply()
  end

  def handle_event("validate-release", %{"deployment_release" => params}, socket) do
    %{
      current_scope: scope,
      deployment_group: deployment_group
    } =
      socket.assigns

    firmware = Firmwares.get_by_id(scope.product, params["firmware"])
    archive = Archives.get_by_id(scope.product, params["archive"])

    changeset = DeploymentRelease.new_changeset(deployment_group, firmware, archive, params, scope.user)

    socket
    |> assign(:form, to_form(changeset, action: :validate))
    |> noreply()
  end

  def handle_event("update-release", %{"deployment_release" => params}, socket) do
    %{
      current_scope: scope,
      deployment_group: deployment_group
    } =
      socket.assigns

    authorized!(:"deployment_group:update", scope)

    firmware = Firmwares.get_by_id(scope.product, params["firmware"])
    archive = Archives.get_by_id(scope.product, params["archive"])

    case ManagedDeployments.create_deployment_release(deployment_group, firmware, archive, scope.user, params) do
      {:ok, {_release, deployment_group}} ->
        AuditLogs.audit!(
          scope.user,
          deployment_group,
          "User #{scope.user.name} updated deployment group #{deployment_group.name}"
        )

        releases = ManagedDeployments.list_deployment_releases(deployment_group)
        changeset = DeploymentRelease.new_changeset(deployment_group)

        socket
        |> assign(:deployment_group, deployment_group)
        |> assign(:releases, releases)
        |> assign(:form, to_form(changeset))
        |> push_event("close-modal", %{id: "new-release"})
        |> send_flash(:info, "Release settings updated")
        |> noreply()

      {:error, changeset} ->
        socket
        |> send_flash(
          :error,
          "An error occurred while updating the release settings. Please check the form for errors."
        )
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  defp firmware_or_archive_value(form_field, mod) do
    cond do
      is_struct(form_field.value, Ecto.Association.NotLoaded) ->
        nil

      is_struct(form_field.value, mod) ->
        form_field.value.id

      is_struct(form_field.value, Ecto.Changeset) ->
        form_field.value.data.id

      true ->
        form_field.value
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

  # keeping some code around while the feature is being developed
  defp rollout_options(assigns) do
    ~H"""
    <div class="border-base-700 hidden w-full border-t pt-6">
      <button
        type="button"
        phx-click="toggle-rollout-options"
        phx-target={@myself}
        class="hover:text-base-100 text-base-300 flex items-center gap-2 text-sm font-medium"
      >
        <svg
          class={["size-4 transition-transform", @show_rollout_options && "rotate-90"]}
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />
        </svg>
        Rollout options
      </button>

      <div :if={@show_rollout_options} class="mt-4 w-1/2">
        <.input
          field={@form[:release_network_interfaces]}
          type="select"
          options={network_interface_options()}
          multiple
          label="Allowed network interfaces"
          hint="Select which network interfaces devices must be on to receive this release. Leave empty to allow all interfaces."
        />

        <div class="mt-4">
          <.input
            field={@form[:release_tags]}
            value={Utils.tags_to_string(@form[:release_tags])}
            label="Release tags"
            placeholder="eg. batch-123, production"
            hint="Devices must have ALL of these tags to receive this release. Leave empty to allow all devices."
          />
        </div>
      </div>
    </div>
    """
  end

  defp send_flash(socket, type, message) do
    send(self(), {:flash, type, message})
    socket
  end

  defp network_interface_options() do
    [
      [key: "Wi-Fi", value: :wifi],
      [key: "Ethernet", value: :ethernet],
      [key: "Cellular", value: :cellular],
      [key: "Unknown", value: :unknown]
    ]
  end
end
