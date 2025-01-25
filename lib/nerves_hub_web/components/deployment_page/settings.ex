defmodule NervesHubWeb.Components.DeploymentPage.Settings do
  use NervesHubWeb, :live_component

  alias NervesHub.Archives
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeploymentTemplates
  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    archives = Archives.all_by_product(assigns.deployment.product)
    firmwares = Firmwares.get_firmwares_for_deployment(assigns.deployment)

    changeset = Deployment.changeset(assigns.deployment, %{})

    socket
    |> assign(assigns)
    |> assign(:archives, archives)
    |> assign(:firmware, assigns.deployment.firmware)
    |> assign(:firmwares, firmwares)
    |> assign(:form, to_form(changeset))
    |> ok()
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-start justify-between gap-4 p-6">
      <.form for={@form} class="w-full flex flex-col gap-4" phx-submit="update-deployment" phx-target={@myself}>
        <div class="w-2/3 flex flex-col bg-zinc-900 border border-zinc-700 rounded">
          <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
            <div class="text-base text-neutral-50 font-medium">General settings</div>
          </div>

          <div class="flex p-6 gap-6">
            <div class="w-1/2 flex flex-col gap-6">
              <.input field={@form[:name]} label="Name" placeholder="Production" />
            </div>
          </div>
        </div>

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
          </div>
        </div>

        <div class="w-2/3 flex flex-col bg-zinc-900 border border-zinc-700 rounded">
          <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
            <div class="text-base text-neutral-50 font-medium">Device matching conditions</div>
          </div>

          <div class="flex flex-col p-6 gap-6">
            <div class="flex flex-col gap-3">
              <p class="text-sm text-zinc-400 w-2/3">
                These conditions are used for matching devices which don't have a configured deployment.
              </p>
              <p class="text-sm text-zinc-400 w-2/3">
                The matching is undertaken when a device connects to the platform.
              </p>
            </div>
            <div class="w-1/2">
              <.input field={@form[:tags]} value={tags_to_string(@form[:conditions])} label="Tag(s) distributed to" placeholder="eg. batch-123" />
            </div>
            <div class="w-1/2">
              <.input field={@form[:version]} value={@form[:conditions].value["version"]} label="Version requirement" placeholder="eg. 1.2.3" />
            </div>
          </div>
        </div>

        <div class="w-2/3 flex flex-col bg-zinc-900 border border-zinc-700 rounded">
          <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
            <div class="text-base text-neutral-50 font-medium">Rolling updates</div>
          </div>

          <div class="flex flex p-6 gap-6">
            <div class="w-1/2 flex flex-col gap-6">
              <.input
                field={@form[:concurrent_updates]}
                label="Concurrent Device Updates"
                type="number"
                hint="The number of devices that will update at any given time. This is a soft limit and concurrent updates may be slightly above this number."
              />
            </div>

            <div class="w-1/2 flex flex-col gap-6">
              <.input
                field={@form[:inflight_update_expiration_minutes]}
                label="Minutes Before Expiring Updates"
                type="number"
                hint="The number of minutes before an inflight update expires to clear the queue."
              />
            </div>
          </div>

          <div class="flex flex-col p-6 gap-8 border-t border-zinc-700">
            <div class="flex gap-6">
              <div class="w-1/2">
                <div phx-feedback-for={@form[:failure_rate].name}>
                  <span class="flex items-end">
                    <.core_label for={@form[:failure_rate_amount].id}>Failure rate</.core_label>
                  </span>
                  <div class="flex items-center gap-2">
                    <input
                      type="number"
                      name={@form[:failure_rate_amount].name}
                      id={@form[:failure_rate_amount].id}
                      value={Phoenix.HTML.Form.normalize_value("number", @form[:failure_rate_amount].value)}
                      class={[
                        "mt-2 py-1.5 px-2 block w-20 rounded text-zinc-400 bg-zinc-900 focus:ring-0 sm:text-sm",
                        "phx-no-feedback:border-zinc-600 phx-no-feedback:focus:border-zinc-700",
                        @form[:failure_rate_amount].errors == [] && "border-zinc-600 focus:border-zinc-700",
                        @form[:failure_rate_amount].errors != [] && "border-red-500 focus:border-red-500"
                      ]}
                    />
                    <div class="text-sm mt-2">devices per</div>
                    <input
                      type="number"
                      name={@form[:failure_rate_seconds].name}
                      id={@form[:failure_rate_seconds].id}
                      value={Phoenix.HTML.Form.normalize_value("number", @form[:failure_rate_seconds].value)}
                      class={[
                        "mt-2 py-1.5 px-2 block w-20 rounded text-zinc-400 bg-zinc-900 focus:ring-0 sm:text-sm",
                        "phx-no-feedback:border-zinc-600 phx-no-feedback:focus:border-zinc-700",
                        @form[:failure_rate_seconds].errors == [] && "border-zinc-600 focus:border-zinc-700",
                        @form[:failure_rate_seconds].errors != [] && "border-red-500 focus:border-red-500"
                      ]}
                    />
                    <div class="text-sm mt-2">sec</div>
                  </div>
                  <div class="flex flex-col gap-1 text-xs text-zinc-400 pt-1">
                    {help_message_for(:failure_rate)}
                  </div>
                  <NervesHubWeb.CoreComponents.error :for={msg <- Enum.map(@form[:failure_rate_amount].errors ++ @form[:failure_rate_seconds].errors, &NervesHubWeb.CoreComponents.translate_error(&1))}>
                    {msg}
                  </NervesHubWeb.CoreComponents.error>
                </div>
              </div>

              <div class="w-1/2">
                <.input field={@form[:failure_threshold]} label="Failure threshold" type="number" hint={help_message_for(:failure_threshold)} />
              </div>
            </div>

            <div class="flex gap-6">
              <div class="w-1/2">
                <div phx-feedback-for={@form[:device_failure_rate_amount].name}>
                  <span class="flex items-end">
                    <.core_label for={@form[:device_failure_rate_amount].id}>Device failure rate</.core_label>
                  </span>
                  <div class="flex items-center gap-2">
                    <input
                      type="number"
                      name={@form[:device_failure_rate_amount].name}
                      id={@form[:device_failure_rate_amount].id}
                      value={Phoenix.HTML.Form.normalize_value("number", @form[:device_failure_rate_amount].value)}
                      class={[
                        "mt-2 py-1.5 px-2 block w-20 rounded text-zinc-400 bg-zinc-900 focus:ring-0 sm:text-sm",
                        "phx-no-feedback:border-zinc-600 phx-no-feedback:focus:border-zinc-700",
                        @form[:device_failure_rate_amount].errors == [] && "border-zinc-600 focus:border-zinc-700",
                        @form[:device_failure_rate_amount].errors != [] && "border-red-500 focus:border-red-500"
                      ]}
                    />
                    <div class="text-sm mt-2">failures per</div>
                    <input
                      type="number"
                      name={@form[:device_failure_rate_seconds].name}
                      id={@form[:device_failure_rate_seconds].id}
                      value={Phoenix.HTML.Form.normalize_value("number", @form[:device_failure_rate_seconds].value)}
                      class={[
                        "mt-2 py-1.5 px-2 block w-20 rounded text-zinc-400 bg-zinc-900 focus:ring-0 sm:text-sm",
                        "phx-no-feedback:border-zinc-600 phx-no-feedback:focus:border-zinc-700",
                        @form[:device_failure_rate_seconds].errors == [] && "border-zinc-600 focus:border-zinc-700",
                        @form[:device_failure_rate_seconds].errors != [] && "border-red-500 focus:border-red-500"
                      ]}
                    />
                    <div class="text-sm mt-2">sec</div>
                  </div>
                  <div class="flex flex-col gap-1 text-xs text-zinc-400 pt-1">
                    {help_message_for(:device_failure_rate)}
                  </div>
                  <.error :for={msg <- Enum.map(@form[:device_failure_rate_amount].errors ++ @form[:device_failure_rate_seconds].errors, &NervesHubWeb.CoreComponents.translate_error(&1))}>
                    {msg}
                  </.error>
                </div>
              </div>

              <div class="w-1/2">
                <.input field={@form[:device_failure_threshold]} label="Device failure threshold" type="number" hint={help_message_for(:device_failure_threshold)} />
              </div>
            </div>

            <div class="flex gap-6">
              <div class="w-1/2">
                <.input field={@form[:penalty_timeout_minutes]} label="Device penalty box timeout minutes" type="number" hint={help_message_for(:penalty_timeout_minutes)} />
              </div>
            </div>
          </div>
        </div>

        <div class="w-2/3 flex flex-col bg-zinc-900 border border-zinc-700 rounded">
          <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
            <div class="text-base text-neutral-50 font-medium">First Connect Code</div>
          </div>

          <div class="flex flex-col p-6 gap-6">
            <div class="w-2/3 flex flex-col gap-6">
              <.input field={@form[:connecting_code]} type="textarea" rows={8} label="Run this code when the device first connects to the console.">
                <:rich_hint>
                  <p>
                    Make sure this is valid Elixir and will not crash the device.
                  </p>
                  <p>
                    This will run before device specific first connect code.
                  </p>
                </:rich_hint>
              </.input>
            </div>
          </div>
        </div>

        <div class="w-2/3 flex flex-col bg-zinc-900 border border-zinc-700 rounded">
          <div class="flex items-center justify-between p-6 gap-6 border-t border-zinc-700">
            <.button style="secondary" type="submit">
              <.icon name="save" /> Save changes
            </.button>

            <.button
              type="link"
              style="danger"
              phx-click="delete-deployment"
              phx-target={@myself}
              aria-label="Delete"
              data-confirm={[
                "Are you sure you want to delete this deployment?",
                @deployment.device_count > 0 && " All devices assigned to this deployment will be assigned a new deployment when they reconnect. ",
                "This cannot be undone."
              ]}
            >
              <.icon name="trash" />Delete
            </.button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("update-deployment", %{"deployment" => params}, socket) do
    %{org_user: org_user, org: org, product: product, user: user, deployment: deployment} =
      socket.assigns

    authorized!(:"deployment:update", org_user)

    params = inject_conditions_map(params)

    case Deployments.update_deployment(deployment, params) do
      {:ok, updated} ->
        # Use original deployment so changes will get
        # marked in audit log
        AuditLogs.audit!(
          user,
          updated,
          "User #{user.name} updated deployment #{updated.name}"
        )

        # TODO: if we move away from slugs with deployment names we won't need
        # to use `push_navigate` here.
        socket
        |> LiveToast.put_toast(:info, "Deployment updated")
        |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/deployments/#{updated.name}")
        |> noreply()

      {:error, changeset} ->
        socket
        |> send_toast(
          :error,
          "An error occurred while updating the Deployment. Please check the form for errors."
        )
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  def handle_event("delete-deployment", _params, socket) do
    authorized!(:"deployment:delete", socket.assigns.org_user)

    %{deployment: deployment, org: org, product: product, user: user} = socket.assigns

    {:ok, _} = Deployments.delete_deployment(deployment)

    _ = DeploymentTemplates.audit_deployment_deleted(user, deployment)

    socket
    |> put_flash(:info, "Deployment successfully deleted")
    |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/deployments")
    |> noreply()
  end

  defp inject_conditions_map(%{"version" => version, "tags" => tags} = params) do
    params
    |> Map.put("conditions", %{
      "version" => version,
      "tags" =>
        tags
        |> tags_as_list()
        |> MapSet.new()
        |> MapSet.to_list()
    })
  end

  defp inject_conditions_map(params), do: params

  defp tags_as_list(""), do: []

  defp tags_as_list(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  def firmware_dropdown_options(firmwares) do
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

  def archive_dropdown_options(acrhives) do
    acrhives
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

  def archive_display_name(%{} = a) do
    "#{a.version} - #{a.platform} - #{a.architecture} (#{String.slice(a.uuid, 0..7)})"
  end

  defp help_message_for(field) do
    case field do
      :failure_threshold ->
        "Maximum number of target devices from this deployment that can be in an unhealthy state before marking the deployment unhealthy."

      :failure_rate ->
        "Maximum number of device install failures from this deployment within X seconds before being marked unhealthy."

      :device_failure_rate ->
        "Maximum number of device failures within X seconds a device can have for this deployment before being marked unhealthy."

      :device_failure_threshold ->
        "Maximum number of install attempts and/or failures a device can have for this deployment before being marked unhealthy."

      :penalty_timeout_minutes ->
        "Number of minutes a device is placed in the penalty box for reaching the failure rate and threshold."
    end
  end

  defp firmware_display_name(%Firmware{} = f) do
    "#{f.version} - #{f.platform} - #{f.architecture} (#{String.slice(f.uuid, 0..7)})"
  end

  @doc """
  Convert tags from a list to a comma-separated list (in a string)
  """
  def tags_to_string(%Phoenix.HTML.FormField{} = field) do
    field.value
    |> Map.get("tags", [])
    |> Enum.join(", ")
  end
end
