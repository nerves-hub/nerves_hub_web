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
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

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
    # Kept across updates from the parent, which would otherwise clear a release
    # edit that's still open
    |> assign_new(:editing_release, fn -> nil end)
    |> assign_new(:connecting_code_form, fn -> nil end)
    |> ok()
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-6 p-6">
      <div class="w-full">
        <div class="bg-surface-raised border-base-700 flex flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base-50 text-base font-medium">Release History</div>

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
                      <.local_datetime at={release.inserted_at} time_zone={@time_zone} format={:long_date} zone_label={false} />
                      <.local_datetime at={release.inserted_at} time_zone={@time_zone} format={:time} class="text-base-500 text-xs" />
                    </div>

                    <span
                      :if={release.required}
                      id={"release-#{release.id}-required"}
                      class="bg-base-800 border-base-700 text-base-300 mt-2 flex h-6 w-fit items-center rounded-full border px-2.5 text-xs font-medium"
                      title="Devices that haven't reached this release are updated to it before any newer release"
                    >
                      Required
                    </span>
                  </div>

                  <div class="flex min-w-0 grow flex-col gap-2 px-4 py-3 text-sm">
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

                    <div class="flex flex-wrap gap-x-4 gap-y-1">
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

                      <div class="text-sm">
                        <span class="text-base-400">Connecting code:</span>
                        <.link
                          :if={release.connecting_code}
                          id={"release-#{release.id}-connecting-code"}
                          phx-click={CoreComponents.show_modal("release-connecting-code-#{release.id}")}
                          class="text-base-300 font-medium underline decoration-dashed hover:decoration-solid"
                        >
                          {connecting_code_mode_summary(release.connecting_code_mode)}
                        </.link>
                        <span :if={!release.connecting_code} class="text-base-400 font-medium">
                          None
                        </span>
                        <CoreComponents.modal :if={release.connecting_code} id={"release-connecting-code-#{release.id}"}>
                          <div class="flex flex-col gap-5 p-4">
                            <h2 class="text-base-300 text-lg font-semibold">Connecting code</h2>
                            <p class="text-base-400 text-sm">
                              {connecting_code_mode_summary(release.connecting_code_mode)}. Devices running this release run it when they connect.
                            </p>
                            <pre class="bg-base-800/50 text-base-300 overflow-x-auto p-5 text-sm">{release.connecting_code}</pre>
                          </div>
                        </CoreComponents.modal>
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

                  <div :if={authorized?(:"deployment_group:update", @current_scope)} class="flex items-center px-4 py-3">
                    <.button id={"release-#{release.id}-edit"} style="secondary" type="button" phx-click={edit_release(release, @myself)}>
                      Edit
                    </.button>
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
            <div class="text-base-50 text-base font-medium">Release settings</div>
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

            <div class="flex w-1/2 flex-col gap-6">
              <.input field={f[:required]} type="checkbox" label="Required release">
                <:rich_hint>
                  Devices that haven't reached this release are updated to it before any newer release. This can be changed later from the release history.
                </:rich_hint>
              </.input>
            </div>

            <.connecting_code_inputs form={f} />

            <.rollout_options show_rollout_options={@show_rollout_options} myself={@myself} />

            <div>
              <.button style="primary" type="submit">
                <.icon name="save" /> Create release
              </.button>
            </div>
          </div>
        </.form>
      </CoreComponents.modal>

      <CoreComponents.modal id="edit-release">
        <div :if={@editing_release}>
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base-50 text-base font-medium">Edit release {@editing_release.number}</div>
          </div>

          <div class="border-base-700 flex flex-col gap-3 border-b p-4">
            <div class="text-base-50 text-sm font-medium">Required release</div>
            <p class="text-base-400 text-sm">
              {if @editing_release.required, do: "This release is required.", else: "This release isn't required."} Devices that haven't reached a required release are updated to it before any newer release.
            </p>
            <div>
              <.button
                id="edit-release-toggle-required"
                style="secondary"
                type="button"
                phx-click="toggle-release-required"
                phx-value-release_id={@editing_release.id}
                phx-target={@myself}
                data-confirm={required_confirmation(@editing_release)}
              >
                {if @editing_release.required, do: "Unmark required", else: "Mark required"}
              </.button>
            </div>
          </div>

          <.form
            :let={f}
            id="connecting-code-form"
            for={@connecting_code_form}
            phx-change="validate-connecting-code"
            phx-submit="save-connecting-code"
            phx-target={@myself}
          >
            <div class="flex flex-col gap-6 p-4">
              <.connecting_code_inputs form={f} />

              <div class="flex gap-2">
                <.button style="primary" type="submit">
                  <.icon name="save" /> Save connecting code
                </.button>

                <.button
                  :if={@editing_release.connecting_code}
                  id="edit-release-remove-connecting-code"
                  style="secondary"
                  type="button"
                  phx-click="remove-connecting-code"
                  phx-target={@myself}
                  data-confirm="Devices running this release will no longer run its connecting code when they connect. Continue?"
                >
                  Remove connecting code
                </.button>
              </div>
            </div>
          </.form>
        </div>
      </CoreComponents.modal>
    </div>
    """
  end

  attr(:form, Form, required: true)

  defp connecting_code_inputs(assigns) do
    ~H"""
    <div class="flex w-2/3 flex-col gap-6">
      <.input field={@form[:connecting_code]} type="textarea" rows={6} label="Connecting code" phx-debounce="500">
        <:rich_hint>
          Runs when a device running this release connects. Make sure this is valid Elixir and will not crash the device.
        </:rich_hint>
      </.input>
    </div>

    <div class="flex w-1/2 flex-col gap-6">
      <.input
        field={@form[:connecting_code_mode]}
        type="select"
        options={connecting_code_mode_options()}
        label="Run order"
        hint="Where this code runs relative to the deployment group's connecting code. Device specific connecting code always runs last."
      />
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

  def handle_event("toggle-release-required", %{"release_id" => release_id}, socket) do
    %{current_scope: scope, releases: releases} = socket.assigns

    authorized!(:"deployment_group:update", scope)

    release = Enum.find(releases, &(to_string(&1.id) == release_id))

    case release && ManagedDeployments.set_deployment_release_required(release, !release.required, scope.user) do
      {:ok, updated} ->
        message =
          if updated.required,
            do: "Release #{updated.number} is now required",
            else: "Release #{updated.number} is no longer required"

        socket
        |> reload_releases()
        |> send_flash(:info, message)
        |> noreply()

      _ ->
        socket
        |> send_flash(:error, "The release could not be updated. Please try again.")
        |> noreply()
    end
  end

  def handle_event("edit-release", %{"release_id" => release_id}, socket) do
    %{current_scope: scope, releases: releases} = socket.assigns

    authorized!(:"deployment_group:update", scope)

    case Enum.find(releases, &(to_string(&1.id) == to_string(release_id))) do
      nil ->
        noreply(socket)

      release ->
        socket
        |> assign(:editing_release, release)
        |> assign(:connecting_code_form, connecting_code_form(release, %{}))
        |> noreply()
    end
  end

  def handle_event("validate-connecting-code", %{"release_connecting_code" => params}, socket) do
    socket
    |> assign(:connecting_code_form, connecting_code_form(socket.assigns.editing_release, params, :validate))
    |> noreply()
  end

  def handle_event("save-connecting-code", %{"release_connecting_code" => params}, socket) do
    save_connecting_code(socket, params, &"Connecting code for release #{&1.number} saved")
  end

  def handle_event("remove-connecting-code", _params, socket) do
    save_connecting_code(socket, %{"connecting_code" => nil}, &"Connecting code removed from release #{&1.number}")
  end

  defp save_connecting_code(socket, params, flash_message) do
    %{current_scope: scope, editing_release: release} = socket.assigns

    authorized!(:"deployment_group:update", scope)

    case ManagedDeployments.update_deployment_release_connecting_code(release, params, scope.user) do
      {:ok, release} ->
        socket
        |> reload_releases()
        |> push_event("close-modal", %{id: "edit-release"})
        |> send_flash(:info, flash_message.(release))
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:connecting_code_form, to_form(changeset, as: :release_connecting_code))
        |> noreply()
    end
  end

  # The release being edited is refreshed along with the list, so an open edit
  # modal shows the change. Its connecting code form is left alone, keeping
  # anything typed there that hasn't been saved.
  defp reload_releases(socket) do
    releases = ManagedDeployments.list_deployment_releases(socket.assigns.deployment_group)

    editing_release =
      socket.assigns.editing_release &&
        Enum.find(releases, socket.assigns.editing_release, &(&1.id == socket.assigns.editing_release.id))

    socket
    |> assign(:releases, releases)
    |> assign(:editing_release, editing_release)
  end

  defp connecting_code_form(release, params, action \\ nil) do
    release
    |> DeploymentRelease.connecting_code_changeset(params)
    |> to_form(as: :release_connecting_code, action: action)
  end

  defp connecting_code_mode_options() do
    [
      [key: "After the deployment group's code", value: :last],
      [key: "Before the deployment group's code", value: :first],
      [key: "Override the deployment group's code", value: :override]
    ]
  end

  defp connecting_code_mode_summary(:last), do: "Runs after the group's code"
  defp connecting_code_mode_summary(:first), do: "Runs before the group's code"
  defp connecting_code_mode_summary(:override), do: "Overrides the group's code"

  defp edit_release(release, myself) do
    %JS{}
    |> JS.push("edit-release", value: %{release_id: release.id}, target: myself)
    |> CoreComponents.show_modal("edit-release")
  end

  defp required_confirmation(%{required: true}) do
    "Devices will no longer be held at this release on their way to newer ones. Continue?"
  end

  defp required_confirmation(%{required: false}) do
    "Devices that haven't reached this release will be updated to it before any newer release. Continue?"
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
