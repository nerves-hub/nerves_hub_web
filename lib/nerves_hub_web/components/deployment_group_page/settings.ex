defmodule NervesHubWeb.Components.DeploymentGroupPage.Settings do
  use NervesHubWeb, :live_component

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Devices
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    changeset = DeploymentGroup.update_changeset(assigns.deployment_group, %{})

    socket
    |> assign(assigns)
    |> allow_upload(:workflow_definition,
      accept: ~w(.json),
      max_entries: 1,
      auto_upload: true,
      progress: &handle_progress/3
    )
    |> assign(:form, to_form(changeset))
    |> assign(:available_tags, Devices.distinct_tags_for_product(assigns.current_scope.product))
    |> ok()
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-start justify-between gap-4 p-6">
      <.form id="deployment-form" for={@form} class="flex w-full flex-col gap-4" phx-change="validate-deployment-group" phx-submit="update-deployment-group" phx-target={@myself}>
        <div class="bg-surface-raised border-base-700 flex w-2/3 flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base-50 text-base font-medium">General settings</div>
          </div>

          <div class="flex gap-6 p-6">
            <div class="flex w-1/2 flex-col gap-6">
              <.input field={@form[:name]} label="Name" placeholder="Production" phx-debounce="blur" />
              <.input field={@form[:delta_updatable]} type="checkbox" label="Delta updates">
                <:rich_hint>
                  When enabled, the deployment group will only send delta updates.
                  Check out the <.link class="underline" href="https://docs.nerves-hub.org/nerves-hub/setup/firmware#delta-updates" target="_blank">NervesHub documentation</.link>
                  for more information on delta updates.
                </:rich_hint>
              </.input>
              <.input field={@form[:lock_device_membership]} type="checkbox" label="Lock device membership">
                <:rich_hint>
                  When enabled, devices will not be automatically assigned to or removed from this deployment group.
                </:rich_hint>
              </.input>
              <.input
                field={@form[:notes]}
                type="textarea"
                rows={4}
                label="Notes"
                placeholder="Why is this deployment group being created?"
                phx-debounce="blur"
              />
            </div>
          </div>
        </div>

        <div class="bg-surface-raised border-base-700 flex w-2/3 flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base-50 text-base font-medium">Device matching conditions</div>
          </div>

          <div class="flex flex-col gap-6 p-6">
            <div class="flex flex-col gap-3">
              <p class="text-base-400 w-2/3 text-sm">
                These conditions are used for matching devices which don't have a configured deployment group.
              </p>
              <p class="text-base-400 w-2/3 text-sm">
                The matching is undertaken when a device connects to the platform.
              </p>
            </div>
            <.inputs_for :let={conditions} field={@form[:conditions]}>
              <div class="w-1/2">
                <.tag_input field={conditions[:tags]} label="Tag(s) distributed to" placeholder="eg. batch-123" available_tags={@available_tags} />
              </div>

              <div class="w-1/2">
                <.input
                  field={conditions[:tag_operator]}
                  type="select"
                  options={[[value: "and", key: "Require all"], [value: "or", key: "Allow any"]]}
                  label="Tag matching"
                  hint="“Allow any” matches devices with at least one of the tags. “Require all” matches only devices that have every tag."
                />
              </div>

              <div class="w-1/2">
                <.input field={conditions[:version]} label="Version requirement" placeholder="eg. 1.2.3" />
              </div>
            </.inputs_for>
          </div>
        </div>

        <div class="bg-surface-raised border-base-700 flex w-2/3 flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base-50 text-base font-medium">Deployment Workflows</div>
          </div>

          <div class="flex flex-col gap-6 p-6">
            <div class="flex flex-col gap-3">
              <p class="text-base-400 w-2/3 text-sm">
                Use continuous deployment workflows for updating devices. These workflows are defined in JSON, similar to how GitHub Actions and CircleCI configs are defined in YML.
              </p>

              <p class="text-base-400 w-2/3 text-sm">
                This is an early release feature, please report all feedback to the <.link href="https://github.com/nerves_hub/nerves_hub_web/issues">NervesHub GitHub issue tracker.</.link>
              </p>

              <p :if={@deployment_group.workflow_definition} class="text-base-400 w-2/3 text-sm font-semibold">
                A Workflow Definition has been uploaded, with {length(@deployment_group.workflow_definition["steps"])} steps.
              </p>
            </div>

            <div class="flex gap-3">
              <div :if={@deployment_group.workflow_definition} class="w-fit">
                <.button
                  type="link"
                  style="danger"
                  phx-click="delete-workflow-definition"
                  phx-target={@myself}
                  aria-label="Delete Workflow Definition"
                  data-confirm="Are you sure you want to delete the current Workflow Definition?"
                >
                  <.icon name="trash" />Delete Workflow Definition
                </.button>
              </div>

              <div class="bg-base-800 border-base-600 flex w-fit shrink gap-2 rounded border px-3 py-1.5 hover:cursor-pointer">
                <svg class="size-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="none">
                  <path
                    d="M4.1665 10.0001H9.99984M15.8332 10.0001H9.99984M9.99984 10.0001V4.16675M9.99984 10.0001V15.8334"
                    stroke="#A1A1AA"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
                <label for={@uploads.workflow_definition.ref} class="text-base-300 text-sm font-medium hover:cursor-pointer">
                  {if is_nil(@deployment_group.workflow_definition), do: "Upload Workflow Definition", else: "Upload New Workflow Definition"}
                </label>
                <.live_file_input upload={@uploads.workflow_definition} class="hidden" />
              </div>
            </div>
          </div>
        </div>

        <div class="bg-base-900 border-base-700 flex w-2/3 flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base-50 text-base font-medium">Device queue settings</div>
          </div>

          <div class="flex flex-col gap-6 p-6">
            <div class="w-1/2">
              <.input
                field={@form[:queue_management]}
                type="select"
                options={[[value: "FIFO", key: "FIFO"], [value: "LIFO", key: "LIFO"]]}
                label="Queue management"
                hint="FIFO (First-In, First-Out) prioritizes devices that have been connected the longest for updates, while LIFO (Last-In, First-Out) prioritizes the most recently connected devices."
              />
            </div>
          </div>
        </div>

        <div class="bg-surface-raised border-base-700 flex w-2/3 flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base-50 text-base font-medium">Rolling updates</div>
          </div>

          <div class="flex gap-6 p-6">
            <div class="flex w-1/2 flex-col gap-6">
              <.input
                field={@form[:concurrent_updates]}
                label="Concurrent Device Updates"
                type="number"
                hint="The number of devices that will update at any given time. This is a soft limit and concurrent updates may be slightly above this number."
              />
            </div>
          </div>
        </div>

        <div class="bg-surface-raised border-base-700 flex w-2/3 flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base-50 text-base font-medium">Priority queue</div>
          </div>

          <div class="flex flex-col gap-6 p-6">
            <div class="flex flex-col gap-3">
              <p class="text-base-400 w-2/3 text-sm">
                Enable priority queue to fast-track devices with older firmware versions (e.g., fresh from factory) for immediate updates, bypassing the normal rolling update queue.
              </p>
            </div>

            <div class="w-1/2">
              <.input
                field={@form[:priority_queue_enabled]}
                type="checkbox"
                label="Enable priority queue"
              />
            </div>

            <div class="w-1/2">
              <.input
                field={@form[:priority_queue_concurrent_updates]}
                label="Priority Queue Concurrent Updates"
                type="number"
                hint="The number of priority devices that will update concurrently, separate from the main concurrent limit."
              />
            </div>

            <div class="w-1/2">
              <.input
                field={@form[:priority_queue_firmware_version_threshold]}
                label="Firmware Version Threshold"
                type="text"
                placeholder="eg. 1.0.0"
                hint="Devices with firmware versions at or below this threshold will be processed via the priority queue. Leave empty to disable."
              />
            </div>
          </div>
        </div>

        <div class="bg-surface-raised border-base-700 flex w-2/3 flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base-50 text-base font-medium">Device penalty box logic</div>
          </div>
          <div class="border-base-700 flex flex-col gap-8 border-t p-6">
            <div>
              <p class="text-base-400 mb-4 w-2/3 text-sm">
                When device update attempts fail consistently, the device is placed in the penalty box. It will not attempt to update until it's removed from the penalty box.
              </p>
              <p class="text-base-400 w-2/3 text-sm">
                There are two ways a device can be removed from the penalty box: after "Device penalty box timeout minutes" have passed or viewing the device and re-enabling "Firmware updates" in the top right of UI. In both cases, device update attempts will resume again.
              </p>
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
                        "bg-base-900 text-base-400 mt-2 block w-20 rounded px-2 py-1.5 focus:ring-0 sm:text-sm",
                        "phx-no-feedback:border-base-600 phx-no-feedback:focus:border-base-700",
                        @form[:device_failure_rate_amount].errors == [] && "border-base-600 focus:border-base-700",
                        @form[:device_failure_rate_amount].errors != [] && "border-alert focus:border-alert"
                      ]}
                    />
                    <div class="mt-2 text-sm">failures per</div>
                    <input
                      type="number"
                      name={@form[:device_failure_rate_seconds].name}
                      id={@form[:device_failure_rate_seconds].id}
                      value={Phoenix.HTML.Form.normalize_value("number", @form[:device_failure_rate_seconds].value)}
                      class={[
                        "bg-base-900 text-base-400 mt-2 block w-20 rounded px-2 py-1.5 focus:ring-0 sm:text-sm",
                        "phx-no-feedback:border-base-600 phx-no-feedback:focus:border-base-700",
                        @form[:device_failure_rate_seconds].errors == [] && "border-base-600 focus:border-base-700",
                        @form[:device_failure_rate_seconds].errors != [] && "border-alert focus:border-alert"
                      ]}
                    />
                    <div class="mt-2 text-sm">sec</div>
                  </div>
                  <div class="text-base-400 flex flex-col gap-1 pt-1 text-xs">
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

        <div class="bg-surface-raised border-base-700 flex w-2/3 flex-col rounded border">
          <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
            <div class="text-base-50 text-base font-medium">First Connect Code</div>
          </div>

          <div class="flex flex-col gap-6 p-6">
            <div class="flex w-2/3 flex-col gap-6">
              <.input field={@form[:connecting_code]} type="textarea" rows={8} label="Run this code when the device first connects to the console." phx-debounce="2000">
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

        <div class="bg-surface-raised border-base-700 flex w-2/3 flex-col rounded border">
          <div class="border-base-700 flex items-center justify-between gap-6 border-t p-6">
            <.button style="primary" type="submit">
              <.icon name="save" /> Save changes
            </.button>

            <.button
              type="link"
              style="danger"
              phx-click="delete"
              aria-label="Delete"
              data-confirm={[
                "Are you sure you want to delete this deployment group?",
                (@deployment_group.device_count > 0 && " All devices assigned to this deployment group will be assigned a new deployment when they reconnect. ") || [],
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

  def handle_progress(:workflow_definition, entry, socket) do
    %{
      current_scope: %{org: org, product: product, user: user},
      deployment_group: deployment_group
    } =
      socket.assigns

    if entry.done? do
      authorized!(:"deployment_group:update", socket.assigns.current_scope)

      [contents] =
        consume_uploaded_entries(socket, :workflow_definition, fn %{path: path}, _entry ->
          {:ok, File.read!(path)}
        end)

      # The file is whatever someone picked, so a decode failure is an ordinary
      # outcome to report rather than something to crash the page over.
      case JSON.decode(contents) do
        {:ok, workflow_definition} ->
          save_workflow_definition(socket, workflow_definition, deployment_group, user, org, product)

        {:error, _reason} ->
          socket
          |> put_flash(:error, "That file could not be read as JSON. Check it for a stray comma or bracket.")
          |> noreply()
      end
    else
      {:noreply, socket}
    end
  end

  defp save_workflow_definition(socket, workflow_definition, deployment_group, user, org, product) do
    case ManagedDeployments.update_deployment_group(
           deployment_group,
           %{workflow_definition: workflow_definition},
           user
         ) do
      {:ok, updated} ->
        # Use original deployment so changes will get
        # marked in audit log
        AuditLogs.audit!(
          user,
          updated,
          "User #{user.name} uploaded a new Workflow definition to the deployment group #{updated.name}"
        )

        socket
        |> put_flash(:info, "Workflow definition uploaded successfully. This will be used with the next release.")
        |> push_navigate(to: ~p"/org/#{org}/#{product}/deployment_groups/#{updated}")
        |> noreply()

      {:error, changeset} ->
        socket
        |> put_flash(:error, workflow_definition_error_message(changeset))
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  # The validator says exactly what is wrong and where, so pass that on instead
  # of asking someone to go and look for it themselves.
  defp workflow_definition_error_message(changeset) do
    changeset.errors
    |> Keyword.get_values(:workflow_definition)
    |> Enum.map(fn {message, _opts} -> message end)
    |> case do
      [] -> "An error occurred while uploading the Workflow definition."
      problems -> "That workflow definition is not valid: " <> Enum.join(problems, "; ")
    end
  end

  @impl Phoenix.LiveComponent

  def handle_event("delete-workflow-definition", _params, socket) do
    %{
      current_scope: %{org: org, product: product, user: user},
      deployment_group: deployment_group
    } =
      socket.assigns

    authorized!(:"deployment_group:update", socket.assigns.current_scope)

    case ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: nil}, user) do
      {:ok, updated} ->
        # Use original deployment so changes will get
        # marked in audit log
        AuditLogs.audit!(
          user,
          updated,
          "User #{user.name} removed the Workflow Definition from the deployment group #{updated.name}"
        )

        socket
        |> put_flash(
          :info,
          "The Workflow Definition was removed successfully. Future releases won't use Workflows when using devices."
        )
        |> push_navigate(to: ~p"/org/#{org}/#{product}/deployment_groups/#{updated}")
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(
          :error,
          "An error occurred while removing the Workflow Definition. Please contact support if this happens again."
        )
        |> noreply()
    end
  end

  def handle_event("validate-deployment-group", %{"deployment_group" => params}, socket) do
    changeset =
      socket.assigns.deployment_group
      |> DeploymentGroup.update_changeset(params)

    socket
    |> assign(:form, to_form(changeset, action: :validate))
    |> noreply()
  end

  def handle_event("update-deployment-group", %{"deployment_group" => params}, socket) do
    %{
      current_scope: %{org: org, product: product, user: user},
      deployment_group: deployment_group
    } =
      socket.assigns

    authorized!(:"deployment_group:update", socket.assigns.current_scope)

    case ManagedDeployments.update_deployment_group(deployment_group, params, user) do
      {:ok, updated} ->
        # Use original deployment so changes will get
        # marked in audit log
        AuditLogs.audit!(
          user,
          updated,
          "User #{user.name} updated deployment group #{updated.name}"
        )

        socket
        |> put_flash(:info, "Deployment Group updated")
        |> push_navigate(to: ~p"/org/#{org}/#{product}/deployment_groups/#{updated}")
        |> noreply()

      {:error, changeset} ->
        socket
        |> put_flash(
          :error,
          "An error occurred while updating the deployment group. Please check the form for errors."
        )
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  def handle_event("delete-deployment-group", _params, socket) do
    authorized!(:"deployment_group:delete", socket.assigns.current_scope)

    %{deployment_group: deployment_group, org: org, product: product, user: user} = socket.assigns

    {:ok, _} = ManagedDeployments.delete_deployment_group(deployment_group)

    DeploymentGroupTemplates.audit_deployment_deleted(user, deployment_group)

    socket
    |> put_flash(:info, "Deployment group successfully deleted")
    |> push_navigate(to: ~p"/org/#{org}/#{product}/deployment_groups")
    |> noreply()
  end

  defp help_message_for(field) do
    case field do
      :device_failure_rate ->
        "Maximum number of update attempts within X seconds a device can have for this deployment group before being placed in penalty box."

      :device_failure_threshold ->
        "Maximum number of update attempts a device can have for this deployment group before being placed in penalty box."

      :penalty_timeout_minutes ->
        "Number of minutes a device is placed in penalty box for reaching the failure rate or threshold."
    end
  end
end
