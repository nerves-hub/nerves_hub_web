defmodule NervesHubWeb.Components.DeploymentGroupPage.Releases do
  @moduledoc """
  A deployment group's Releases tab: every release the group has made, newest
  first, and the New release and Edit release dialogs.

  Each row says what the release sent (its firmware, archive, delta updates and
  connecting code), where it stands, and who made it. Opening a row shows its
  notes, its connecting code, and its delta updates, one sub-row per version
  devices update from, on the table's own columns. The current release starts
  open.

  New release opens from `?new=release`, which the page header's button patches
  to from any tab. Edit release changes what can still change on a release:
  whether it's required, and its connecting code. Firmware, archive,
  description and notes stay as they were released.
  """
  use NervesHubWeb, :live_component
  use Gettext, backend: NervesHubWeb.Gettext

  import NervesHubWeb.Components.Fleet, only: [delimited: 1, count_noun: 3]
  import NervesHubWeb.Components.ProductList, only: [format_megabytes: 1]
  import NervesHubWeb.Helpers.FirmwareDeletion, only: [deleted_summary: 2]

  alias NervesHub.Archives
  alias NervesHub.Archives.Archive
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHubWeb.Components.DeploymentGroups
  alias NervesHubWeb.Components.Dialog
  alias NervesHubWeb.Components.Switch
  alias NervesHubWeb.CoreComponents
  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @description_max 100
  @notes_max 1_000

  @impl Phoenix.LiveComponent
  def update(%{event: {:firmware_created, firmware}}, socket) do
    socket
    |> refresh_firmware_choices(
      "New firmware #{firmware.version} (#{String.slice(firmware.uuid, 0..7)}) is available for selection"
    )
    |> ok()
  end

  def update(%{event: {:firmware_deleted, firmware}}, socket) do
    socket
    |> refresh_firmware_choices(
      "Firmware list has been updated. Firmware #{firmware.version} (#{String.slice(firmware.uuid, 0..7)}) has been deleted by another user."
    )
    |> ok()
  end

  def update(%{event: :delta_status_updated}, socket) do
    socket
    |> assign(:delta_counts, ManagedDeployments.release_delta_counts(socket.assigns.deployment_group))
    |> load_deltas()
    |> ok()
  end

  # The page refreshes every few seconds and hands down a fresh group each time,
  # so anything typed into a dialog is kept here rather than rebuilt: the new
  # release's form is made when its dialog opens, and the edit form when Edit
  # is clicked.
  def update(assigns, socket) do
    opening? = assigns.open_new_release and not Map.get(socket.assigns, :open_new_release, false)

    socket
    |> assign(assigns)
    |> assign(:releases, ManagedDeployments.list_deployment_releases(assigns.deployment_group))
    |> assign(:delta_counts, ManagedDeployments.release_delta_counts(assigns.deployment_group))
    |> assign_new(:expanded, fn -> MapSet.new([assigns.deployment_group.current_deployment_release_id]) end)
    |> assign_new(:deltas, fn -> %{} end)
    |> assign_new(:new_form, fn -> nil end)
    |> assign_new(:firmwares, fn -> [] end)
    |> assign_new(:archives, fn -> [] end)
    |> assign_new(:show_connecting_code, fn -> false end)
    |> assign_new(:editing_id, fn -> nil end)
    |> assign_new(:edit_form, fn -> nil end)
    |> assign_new(:deleting_delta, fn -> nil end)
    |> load_deltas()
    |> then(&if(opening?, do: start_new_release(&1), else: &1))
    |> ok()
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns =
      assign(assigns,
        rows: rows(assigns.releases),
        any_required?: Enum.any?(assigns.releases, & &1.required),
        editing: assigns.editing_id && Enum.find(assigns.releases, &(&1.id == assigns.editing_id))
      )

    ~H"""
    <div id="deployment-group-releases" class="flex flex-col gap-3 p-4 sm:p-6">
      <section aria-label="Releases" class="overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card">
        <div class={[
          "h-9 border-b border-line-default bg-surface-muted px-4 text-label text-content-faint uppercase max-sm:hidden",
          "sm:grid sm:grid-cols-[8rem_minmax(0,1fr)_11rem_11rem_1rem] sm:items-center sm:gap-x-4"
        ]}>
          <span>Release</span>
          <span>What’s in it</span>
          <span>Status</span>
          <span>Released by</span>
        </div>

        <p :if={@releases == []} class="px-4 py-10 text-center text-ui text-content-muted">
          No releases yet.
        </p>

        <div :for={{release, replaced_at} <- @rows} id={"release-#{release.id}"} class="border-b border-line-subtle last:border-0">
          <.summary
            release={release}
            replaced_at={replaced_at}
            current?={release.id == @deployment_group.current_deployment_release_id}
            open?={MapSet.member?(@expanded, release.id)}
            entry={@entry}
            delta_counts={@delta_counts[release.id]}
            time_zone={@time_zone}
            myself={@myself}
          />
          <.details
            :if={MapSet.member?(@expanded, release.id)}
            release={release}
            deltas={Map.get(@deltas, release.id, [])}
            sends_deltas?={@deployment_group.delta_updatable}
            current_scope={@current_scope}
            time_zone={@time_zone}
            myself={@myself}
          />
        </div>
      </section>

      <p :if={@any_required?} class="flex items-center gap-2 text-xs text-content-muted">
        <.badge tone="warning">Required</.badge>
        A device that hasn’t reached a required release gets it before any newer one.
      </p>

      <.new_release_dialog
        :if={@open_new_release && @new_form}
        form={@new_form}
        deployment_group={@deployment_group}
        entry={@entry}
        firmwares={@firmwares}
        archives={@archives}
        show_connecting_code={@show_connecting_code}
        current_scope={@current_scope}
        myself={@myself}
      />

      <.edit_release_dialog :if={@editing && @edit_form} release={@editing} form={@edit_form} myself={@myself} />

      <.delete_delta_dialog :if={@deleting_delta} delta={@deleting_delta} myself={@myself} />
    </div>
    """
  end

  attr(:release, DeploymentRelease, required: true)
  attr(:replaced_at, :any, required: true)
  attr(:current?, :boolean, required: true)
  attr(:open?, :boolean, required: true)
  attr(:entry, :map, required: true)
  attr(:delta_counts, :map, default: nil)
  attr(:time_zone, :string, required: true)
  attr(:myself, :any, required: true)

  defp summary(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle-release"
      phx-value-id={@release.id}
      phx-target={@myself}
      aria-expanded={to_string(@open?)}
      aria-controls={"release-#{@release.id}-details"}
      class={[
        "relative flex w-full cursor-pointer flex-col gap-2 px-4 py-2.5 text-left hover:bg-surface-muted sm:min-h-13",
        "focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-focus-ring",
        "sm:grid sm:grid-cols-[8rem_minmax(0,1fr)_11rem_11rem_1rem] sm:items-start sm:gap-x-4 sm:gap-y-0"
      ]}
    >
      <span class="flex flex-col gap-0.5 max-sm:pr-8">
        <span class="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span class="font-mono text-ui/4 font-medium text-content-strong">{@release.firmware.version}</span>
          <.badge :if={@release.required} id={"release-#{@release.id}-required"} tone="warning">Required</.badge>
          <.badge :if={Firmware.deleted?(@release.firmware)} id={"release-#{@release.id}-deleted"}>Deleted</.badge>
        </span>
        <span class="text-xs/4 text-content-muted">Release {@release.number}</span>
      </span>

      <span class="flex min-w-0 flex-col gap-0.5">
        <span :if={present?(@release.description)} class="text-ui/4 font-medium wrap-break-word text-content-strong">{@release.description}</span>
        <span :if={!present?(@release.description)} class="text-ui/4 text-content-faint">No description</span>
        <span class="text-xs/4 text-content-muted">
          <.contents release={@release} delta_counts={@delta_counts} />
        </span>
      </span>

      <span class="text-ui/4 text-content-muted">
        <DeploymentGroups.status_badge :if={@current?} status={@entry.status} />
        <span :if={!@current? && @replaced_at}>Replaced {day_label(@replaced_at, @time_zone)}</span>
      </span>

      <span class="flex flex-col gap-0.5 max-sm:flex-row max-sm:gap-1">
        <span :if={@release.created_by} class="text-ui/4 text-content-strong">{@release.created_by.name}</span>
        <span :if={!@release.created_by && @release.created_by_api_key} class="text-ui/4 text-content-strong">
          API key {@release.created_by_api_key.name}
        </span>
        <span :if={!@release.created_by && !@release.created_by_api_key} class="text-ui/4 text-content-faint">Unknown</span>
        <span class="text-xs/4 text-content-muted max-sm:text-ui/4">
          <span class="sm:hidden">· </span>{to_local_string(@release.inserted_at, @time_zone, :short_datetime, false)}
        </span>
      </span>

      <span
        class={[
          "lucide-chevron-down size-4 text-content-faint transition-transform max-sm:absolute max-sm:top-3 max-sm:right-4",
          @open? && "rotate-180"
        ]}
        aria-hidden="true"
      ></span>
    </button>
    """
  end

  attr(:release, DeploymentRelease, required: true)
  attr(:delta_counts, :map, default: nil)

  # "Archive 1.6.0 · 2 delta updates, 1 failed · Connecting code", or
  # "Firmware only" for a release that sent nothing else.
  defp contents(assigns) do
    parts =
      Enum.reject(
        [
          assigns.release.archive && :archive,
          assigns.delta_counts && :deltas,
          present?(assigns.release.connecting_code) && :connecting_code
        ],
        &(&1 in [nil, false])
      )

    assigns = assign(assigns, :parts, parts)

    ~H"""
    <span :if={@parts == []}>Firmware only</span>
    <%= for {part, index} <- Enum.with_index(@parts) do %>
      <span :if={index > 0}> · </span><.content_part part={part} release={@release} delta_counts={@delta_counts} />
    <% end %>
    """
  end

  attr(:part, :atom, required: true)
  attr(:release, DeploymentRelease, required: true)
  attr(:delta_counts, :map, default: nil)

  defp content_part(%{part: :archive} = assigns) do
    ~H"""
    <span>Archive <span class="font-mono">{@release.archive.version}</span></span>
    """
  end

  defp content_part(%{part: :deltas} = assigns) do
    ~H"""
    <span id={"release-#{@release.id}-delta-count"}>
      {ngettext("1 delta update", "%{count} delta updates", @delta_counts.total)}<span :if={@delta_counts.failed > 0}>, <span class="text-alert-content">{delimited(@delta_counts.failed)} failed</span></span>
    </span>
    """
  end

  defp content_part(%{part: :connecting_code} = assigns) do
    ~H"""
    <span>Connecting code</span>
    """
  end

  attr(:release, DeploymentRelease, required: true)
  attr(:deltas, :list, required: true)
  attr(:sends_deltas?, :boolean, required: true)
  attr(:current_scope, :map, required: true)
  attr(:time_zone, :string, required: true)
  attr(:myself, :any, required: true)

  defp details(assigns) do
    ~H"""
    <div
      id={"release-#{@release.id}-details"}
      class="px-4 pb-4 sm:grid sm:grid-cols-[8rem_minmax(0,1fr)_11rem_11rem_1rem] sm:gap-x-4"
    >
      <div class="flex min-w-0 flex-col gap-4 sm:col-span-3 sm:col-start-2">
        <div :if={present?(@release.notes)} class="flex flex-col gap-1.5">
          <span class="text-xs/4 text-content-muted">Notes</span>
          <p class="max-w-160 text-ui/5 whitespace-pre-line text-content-body">{@release.notes}</p>
        </div>

        <div :if={present?(@release.connecting_code)} class="flex max-w-160 flex-col gap-1.5">
          <span id={"release-#{@release.id}-connecting-code"} class="text-xs/4 text-content-muted">
            Connecting code · {connecting_code_mode_summary(@release.connecting_code_mode)}
          </span>
          <pre class="overflow-x-auto rounded-card border border-line-default bg-surface-muted px-3 py-2.5 font-mono text-xs/5 text-content-strong">{@release.connecting_code}</pre>
        </div>

        <div :if={@deltas != []} id={"release-#{@release.id}-deltas"} class="flex flex-col">
          <span class="pb-1.5 text-xs/4 text-content-muted">Delta updates</span>
          <div
            :for={delta <- @deltas}
            id={"release-delta-#{delta.id}"}
            class="flex min-h-10 flex-wrap items-center gap-x-4 gap-y-1 border-t border-line-subtle py-1.5 text-ui/4 sm:grid sm:grid-cols-[minmax(0,1fr)_11rem_11rem]"
          >
            <span class="flex min-w-0 flex-wrap items-baseline gap-x-6 gap-y-0.5">
              <span class="w-24 shrink-0 text-content-body">From <span class="font-mono">{delta.source.version}</span></span>
              <.delta_detail delta={delta} firmware={@release.firmware} sends_deltas?={@sends_deltas?} />
            </span>
            <.delta_status status={delta.status} />
            <span :if={authorized?(:"deployment_group:release:manage", @current_scope)} class="flex">
              <.button
                :if={delta.status in [:failed, :timed_out]}
                size="sm"
                phx-click="retry-delta"
                phx-value-id={delta.id}
                phx-target={@myself}
              >
                Retry
              </.button>
              <.button
                :if={delta.status == :completed}
                size="sm"
                style="danger"
                phx-click="ask-delete-delta"
                phx-value-id={delta.id}
                phx-target={@myself}
              >
                Delete
              </.button>
            </span>
          </div>
          <p :if={@release.firmware.size} class="border-t border-line-subtle pt-2 text-xs/4 text-content-muted">
            Devices on any other version get the full <span class="font-mono">{format_megabytes(@release.firmware.size)}</span>.
          </p>
        </div>

        <div class="flex flex-wrap items-center gap-x-4 gap-y-2 pt-1">
          <.button
            :if={authorized?(:"deployment_group:release:manage", @current_scope)}
            id={"release-#{@release.id}-edit"}
            size="sm"
            phx-click="edit-release"
            phx-value-id={@release.id}
            phx-target={@myself}
          >
            <span class="lucide-pencil" aria-hidden="true"></span> Edit release
          </.button>
          <span class="flex flex-wrap items-center gap-1.5 text-xs/4 text-content-muted">
            Firmware
            <.link
              navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/firmware/#{@release.firmware.uuid}"}
              class="font-mono text-notice-content hover:underline"
            >
              {@release.firmware.version}
            </.link>
            · <span class="font-mono">{String.slice(@release.firmware.uuid, 0..7)}</span>
            <%!-- Release history outlives the firmware it names. The link still
            resolves, since the firmware page renders its own deleted state. --%>
            <span :if={Firmware.deleted?(@release.firmware)} title={deleted_summary(@release.firmware, @time_zone)}>
              · deleted
            </span>
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr(:delta, :map, required: true)
  attr(:firmware, Firmware, required: true)
  attr(:sends_deltas?, :boolean, required: true)

  defp delta_detail(%{delta: %{status: :completed}} = assigns) do
    ~H"""
    <span class="text-xs/4 text-content-muted">
      <span class="font-mono">{format_megabytes(@delta.size)}</span>
      <span :if={smaller = percent_smaller(@delta)}> · {smaller}% smaller</span>
    </span>
    """
  end

  defp delta_detail(%{delta: %{status: :processing}} = assigns) do
    ~H"""
    <span class="text-xs/4 text-content-muted">Building from <span class="font-mono">{@delta.source.version}</span></span>
    """
  end

  # A failed delta holds back the devices waiting for it, until it is built
  # again or delta updates are turned off (`Updates.available_for_update/2`).
  # Firmware that can't be delta updated is sent whole whatever its deltas say.
  defp delta_detail(%{sends_deltas?: true, firmware: %Firmware{delta_updatable: true}} = assigns) do
    ~H"""
    <span class="text-xs/4 text-content-muted">
      Devices on <span class="font-mono">{@delta.source.version}</span>
      wait for a retry, or get the full <span :if={@firmware.size} class="font-mono">{format_megabytes(@firmware.size)}</span><span :if={!@firmware.size}>firmware</span>
      with delta updates off
    </span>
    """
  end

  defp delta_detail(assigns) do
    ~H"""
    <span class="text-xs/4 text-content-muted">
      Devices on <span class="font-mono">{@delta.source.version}</span>
      get the full <span :if={@firmware.size} class="font-mono">{format_megabytes(@firmware.size)}</span><span :if={!@firmware.size}>firmware</span>
    </span>
    """
  end

  attr(:status, :atom, required: true)

  defp delta_status(%{status: :completed} = assigns) do
    ~H"""
    <span class="flex items-center gap-1.5 text-content-body"><span class="lucide-circle-check--bold size-3.5 text-success" aria-hidden="true"></span>Ready</span>
    """
  end

  defp delta_status(%{status: :processing} = assigns) do
    ~H"""
    <span class="flex items-center gap-1.5 text-content-body">
      <span class="lucide-loader-circle--bold size-3.5 animate-spin text-content-muted motion-reduce:animate-none" aria-hidden="true"></span>Building
    </span>
    """
  end

  defp delta_status(assigns) do
    ~H"""
    <span class="flex items-center gap-1.5 text-content-body">
      <span class="lucide-circle-x--bold size-3.5 text-alert" aria-hidden="true"></span>{(@status == :timed_out && "Timed out") || "Failed"}
    </span>
    """
  end

  attr(:form, Form, required: true)
  attr(:deployment_group, :map, required: true)
  attr(:entry, :map, required: true)
  attr(:firmwares, :list, required: true)
  attr(:archives, :list, required: true)
  attr(:show_connecting_code, :boolean, required: true)
  attr(:current_scope, :map, required: true)
  attr(:myself, :any, required: true)

  defp new_release_dialog(assigns) do
    current = assigns.deployment_group.current_release
    firmware_id = field_id(assigns.form[:firmware], Firmware)

    assigns =
      assign(assigns,
        current: current,
        firmware: Enum.find(assigns.firmwares, &(&1.id == firmware_id)),
        archive_id: field_id(assigns.form[:archive], Archive)
      )

    ~H"""
    <Dialog.form_dialog
      id="new-release"
      title={"New release for #{@deployment_group.name}"}
      on_cancel={JS.patch(releases_path(@current_scope, @deployment_group))}
    >
      <:subtitle>The group starts sending it as soon as it’s created.</:subtitle>
      <.form :let={f} for={@form} id="release-form" phx-change="validate-release" phx-submit="create-release" phx-target={@myself}>
        <Dialog.form_body>
          <.field field={f[:firmware]} label="Firmware">
            <:help>
              For <span class="font-mono">{@current.firmware.platform} · {@current.firmware.architecture}</span>, newest first
            </:help>
            <DeploymentGroups.select_control
              id={f[:firmware].id}
              name={f[:firmware].name}
              error={error?(f[:firmware])}
              aria-describedby={"#{f[:firmware].id}-hint"}
            >
              <option value="">Choose firmware</option>
              {Form.options_for_select(firmware_options(@firmwares), field_id(f[:firmware], Firmware))}
            </DeploymentGroups.select_control>
          </.field>

          <.field field={f[:description]} label="Description">
            <:counter>{text_length(f[:description].value)}/{description_max()}</:counter>
            <input
              type="text"
              id={f[:description].id}
              name={f[:description].name}
              value={f[:description].value}
              class={DeploymentGroups.field_class(error?(f[:description]))}
            />
          </.field>

          <.field field={f[:notes]} label="Notes" optional>
            <:counter>{text_length(f[:notes].value)}/{delimited(notes_max())}</:counter>
            <textarea
              id={f[:notes].id}
              name={f[:notes].name}
              rows="3"
              class={DeploymentGroups.textarea_class(error?(f[:notes]))}
            >{Form.normalize_value("textarea", f[:notes].value)}</textarea>
          </.field>

          <.field field={f[:archive]} label="Archive" optional>
            <:help>Sent to devices along with the firmware</:help>
            <DeploymentGroups.select_control
              id={f[:archive].id}
              name={f[:archive].name}
              error={error?(f[:archive])}
              aria-describedby={"#{f[:archive].id}-hint"}
            >
              <option value="">None</option>
              {Form.options_for_select(archive_options(@archives, @current), @archive_id)}
            </DeploymentGroups.select_control>
          </.field>

          <div class="flex flex-col rounded-card border border-line-default">
            <.required_switch form={f} id="new-release-required" />
            <div class="border-t border-line-subtle">
              <button
                type="button"
                phx-click="toggle-new-connecting-code"
                phx-target={@myself}
                aria-expanded={to_string(@show_connecting_code)}
                class="flex w-full cursor-pointer items-start gap-2.5 px-4 py-3 text-left focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-focus-ring"
              >
                <span class={["lucide-chevron-right size-4 text-content-faint transition-transform", @show_connecting_code && "rotate-90"]} aria-hidden="true"></span>
                <span class="flex flex-col gap-1">
                  <span class="text-ui/4 font-medium text-content-body">Connecting code</span>
                  <span class="text-xs/4 text-content-muted">Elixir run in each device’s console when it first connects, with or instead of the group’s.</span>
                </span>
              </button>
              <div :if={@show_connecting_code} class="flex flex-col gap-4 px-4 pb-4">
                <.connecting_code_fields form={f} />
              </div>
            </div>
          </div>

          <.what_happens entry={@entry} deployment_group={@deployment_group} firmware={@firmware} />
        </Dialog.form_body>

        <Dialog.form_footer dialog="new-release">
          <.button style="primary" type="submit"><span class="lucide-plus" aria-hidden="true"></span> Create release</.button>
        </Dialog.form_footer>
      </.form>
    </Dialog.form_dialog>
    """
  end

  attr(:delta, :map, required: true)
  attr(:myself, :any, required: true)

  # A delta is built from one firmware to another and every group sending the
  # target shares it, so deleting it here deletes it for all of them.
  defp delete_delta_dialog(assigns) do
    ~H"""
    <Dialog.confirm id="delete-delta" on_cancel={JS.push("cancel-delete-delta", target: @myself)}>
      <:heading>Delete the delta from <span class="font-mono">{@delta.source.version}</span>?</:heading>
      <:subtitle>
        <span class="font-mono">{@delta.source.version} → {@delta.target.version} · {format_megabytes(@delta.size)}</span>
      </:subtitle>
      <p>
        Devices on <span class="font-mono text-content-strong">{@delta.source.version}</span>
        get the full <span :if={@delta.target.size}>{format_megabytes(@delta.target.size)} of </span><span class="font-mono text-content-strong">{@delta.target.version}</span>
        instead. Every deployment group sending <span class="font-mono text-content-strong">{@delta.target.version}</span>
        shares this delta, so that goes for all of them.
      </p>
      <:actions>
        <.button style="danger-solid" phx-click="delete-delta" phx-value-id={@delta.id} phx-target={@myself}>Delete delta</.button>
      </:actions>
    </Dialog.confirm>
    """
  end

  attr(:release, DeploymentRelease, required: true)
  attr(:form, Form, required: true)
  attr(:myself, :any, required: true)

  defp edit_release_dialog(assigns) do
    ~H"""
    <Dialog.form_dialog id="edit-release" title={"Edit release #{@release.number}"} on_cancel={JS.push("close-edit", target: @myself)}>
      <:subtitle>
        <span class="font-mono">{@release.firmware.version}</span><span :if={present?(@release.description)}> · {@release.description}</span>
      </:subtitle>
      <.form :let={f} for={@form} id="edit-release-form" phx-change="validate-edit" phx-submit="save-release" phx-target={@myself}>
        <Dialog.form_body>
          <div class="rounded-card border border-line-default">
            <.required_switch form={f} id="edit-release-required" />
          </div>

          <.connecting_code_fields
            form={f}
            removing={if present?(@release.connecting_code) and not present?(f[:connecting_code].value), do: @release}
          />

          <p class="flex items-start gap-2.5 rounded-md bg-surface-muted p-3 text-ui/4.5 text-content-body">
            <span class="mt-px lucide-lock size-4 text-notice" aria-hidden="true"></span> The firmware, archive, description and notes stay as they were released. To change those, make a new release.
          </p>
        </Dialog.form_body>

        <Dialog.form_footer dialog="edit-release">
          <:start>
            <.button
              :if={present?(f[:connecting_code].value)}
              id="edit-release-remove-connecting-code"
              style="danger"
              phx-click="remove-connecting-code"
              phx-target={@myself}
              class="mr-auto max-sm:mr-0"
            >
              Remove connecting code
            </.button>
          </:start>
          <.button style="primary" type="submit">Save changes</.button>
        </Dialog.form_footer>
      </.form>
    </Dialog.form_dialog>
    """
  end

  attr(:form, Form, required: true)
  attr(:id, :string, required: true)

  defp required_switch(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4 px-4 py-3">
      <div class="flex flex-col gap-1">
        <label for={@id} class="cursor-pointer text-ui/4 font-medium text-content-body">Required release</label>
        <span id={"#{@id}-hint"} class="text-xs/4 text-content-muted">A device that hasn’t reached it gets it before any newer release.</span>
      </div>
      <input type="hidden" name={@form[:required].name} value="false" />
      <Switch.switch
        id={@id}
        name={@form[:required].name}
        value="true"
        checked={Form.normalize_value("checkbox", @form[:required].value)}
        aria-describedby={"#{@id}-hint"}
      />
    </div>
    """
  end

  attr(:form, Form, required: true)

  attr(:removing, :any,
    default: nil,
    doc: "the release being edited, when saving would remove its connecting code"
  )

  defp connecting_code_fields(assigns) do
    ~H"""
    <.field field={@form[:connecting_code]} label="Connecting code">
      <:help :if={!@removing}>Elixir, run in the console when a device first connects</:help>
      <:help :if={@removing}>
        <span class="text-content-body">
          Saving removes release {@removing.number}’s connecting code. Devices won’t run it when they connect.
        </span>
      </:help>
      <textarea
        id={@form[:connecting_code].id}
        name={@form[:connecting_code].name}
        rows="5"
        phx-debounce="500"
        spellcheck="false"
        aria-describedby={"#{@form[:connecting_code].id}-hint"}
        class={DeploymentGroups.textarea_class(error?(@form[:connecting_code]), "font-mono")}
      >{Form.normalize_value("textarea", @form[:connecting_code].value)}</textarea>
    </.field>

    <.field field={@form[:connecting_code_mode]} label="Runs">
      <:help>The group’s code is in its settings.</:help>
      <DeploymentGroups.select_control
        id={@form[:connecting_code_mode].id}
        name={@form[:connecting_code_mode].name}
        error={error?(@form[:connecting_code_mode])}
        aria-describedby={"#{@form[:connecting_code_mode].id}-hint"}
      >
        {Form.options_for_select(connecting_code_mode_options(), @form[:connecting_code_mode].value)}
      </DeploymentGroups.select_control>
    </.field>
    """
  end

  attr(:entry, :map, required: true)
  attr(:deployment_group, :map, required: true)
  attr(:firmware, :any, required: true)

  # What creating the release sets off, from what the page already knows.
  defp what_happens(assigns) do
    current = assigns.deployment_group.current_release

    assigns =
      assign(assigns,
        current: current,
        behind: max(assigns.entry.counts.total - assigns.entry.counts.updated, 0),
        first_step: List.first(assigns.entry.steps)
      )

    ~H"""
    <ul id="new-release-what-happens" class="flex flex-col gap-1.5 rounded-md bg-surface-muted p-3 text-ui/4.5 text-content-body">
      <li class="flex gap-2">
        <span class="mt-1.75 size-1 shrink-0 rounded-full bg-content-faint" aria-hidden="true"></span>
        <span>
          Replaces <span class="font-mono">{@current.firmware.version}</span><.held entry={@entry} />.
          <span :if={@behind > 0}>
            The {count_noun(@behind, "device", "devices")} that {if @behind == 1, do: "doesn’t", else: "don’t"} have it will get <.new_version firmware={@firmware} /> instead.
          </span>
        </span>
      </li>
      <li class="flex gap-2">
        <span class="mt-1.75 size-1 shrink-0 rounded-full bg-content-faint" aria-hidden="true"></span>
        <span :if={@first_step}>Starts again at step 1, {DeploymentGroups.step_name(@first_step)}.</span>
        <span :if={!@first_step}>Every device that matches gets it the next time it connects.</span>
      </li>
      <li class="flex gap-2">
        <span class="mt-1.75 size-1 shrink-0 rounded-full bg-content-faint" aria-hidden="true"></span>
        <span :if={@deployment_group.delta_updatable}>Delta updates get built from the versions the group’s devices are on.</span>
        <span :if={!@deployment_group.delta_updatable}>Delta updates are off, so devices download the full firmware.</span>
      </li>
    </ul>
    """
  end

  attr(:entry, :map, required: true)

  defp held(%{entry: %{status: :awaiting_approval, awaiting_step: %{} = step}} = assigns) do
    assigns = assign(assigns, :step, step)

    ~H"""
    , which is waiting at {DeploymentGroups.step_name(@step)}
    """
  end

  defp held(%{entry: %{status: :stopped, failed_step: %{} = step}} = assigns) do
    assigns = assign(assigns, :step, step)

    ~H"""
    , which stopped at {DeploymentGroups.step_name(@step)}
    """
  end

  defp held(assigns), do: ~H""

  attr(:firmware, :any, required: true)

  defp new_version(%{firmware: %Firmware{}} = assigns) do
    ~H"""
    <span class="font-mono">{@firmware.version}</span>
    """
  end

  defp new_version(assigns), do: ~H"the new firmware"

  attr(:field, FormField, required: true)
  attr(:label, :string, required: true)
  attr(:optional, :boolean, default: false)
  slot(:help, doc: "what to know about the field; the control's `aria-describedby` is the field's id with `-hint`")
  slot(:counter, doc: "how much of its limit the value uses, at the far end under the control")
  slot(:inner_block, required: true)

  # A label over the control, the field's errors once it's been used, and what
  # to know about it underneath.
  defp field(assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <label for={@field.id} class="text-ui/4 font-medium text-content-body">
        {@label}<span :if={@optional} class="font-normal text-content-muted"> · optional</span>
      </label>
      {render_slot(@inner_block)}
      <DeploymentGroups.field_error :for={message <- field_errors(@field)}>{message}</DeploymentGroups.field_error>
      <div :if={@help != [] or @counter != []} class="flex items-start gap-4 text-xs/4 text-content-muted">
        <span :for={help <- @help} id={"#{@field.id}-hint"}>{render_slot(help)}</span>
        <span :for={counter <- @counter} class="ml-auto font-mono tabular-nums">{render_slot(counter)}</span>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  @decorate requires_membership()
  def handle_event("toggle-release", %{"id" => id}, socket) do
    case find_release(socket, id) do
      nil ->
        noreply(socket)

      release ->
        expanded = socket.assigns.expanded

        expanded =
          if MapSet.member?(expanded, release.id),
            do: MapSet.delete(expanded, release.id),
            else: MapSet.put(expanded, release.id)

        socket
        |> assign(:expanded, expanded)
        |> load_deltas()
        |> noreply()
    end
  end

  @decorate requires_membership()
  def handle_event("toggle-new-connecting-code", _params, socket) do
    socket
    |> assign(:show_connecting_code, !socket.assigns.show_connecting_code)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("validate-release", %{"deployment_release" => params}, socket) do
    socket
    |> assign(:new_form, new_release_form(socket, params, :validate))
    |> noreply()
  end

  @decorate requires_permission(:"deployment_group:release:manage")
  def handle_event("create-release", %{"deployment_release" => params}, socket) do
    %{current_scope: scope, deployment_group: deployment_group} = socket.assigns

    firmware = Firmwares.get_by_id(scope.product, params["firmware"])
    archive = Archives.get_by_id(scope.product, params["archive"])

    case ManagedDeployments.create_deployment_release(deployment_group, firmware, archive, scope.user, params) do
      {:ok, {release, _deployment_group}} ->
        socket
        |> assign(:expanded, MapSet.new([release.id]))
        |> assign(:new_form, nil)
        |> send_flash(:info, "Release #{release.number} created with #{firmware.version}")
        |> push_patch(to: releases_path(scope, deployment_group))
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(:new_form, to_form(changeset, action: :insert))
        |> noreply()

      {:error, _reason} ->
        socket
        |> send_flash(:error, "The release could not be created. Please try again.")
        |> noreply()
    end
  end

  @decorate requires_permission(:"deployment_group:release:manage")
  def handle_event("edit-release", %{"id" => id}, socket) do
    case find_release(socket, id) do
      nil ->
        noreply(socket)

      release ->
        socket
        |> assign(:editing_id, release.id)
        |> assign(:edit_form, edit_form(release, %{}))
        |> noreply()
    end
  end

  @decorate requires_membership()
  def handle_event("close-edit", _params, socket) do
    socket
    |> assign(:editing_id, nil)
    |> assign(:edit_form, nil)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("validate-edit", %{"release" => params}, socket) do
    case editing_release(socket) do
      nil -> noreply(socket)
      release -> socket |> assign(:edit_form, edit_form(release, params, :validate)) |> noreply()
    end
  end

  @decorate requires_permission(:"deployment_group:release:manage")
  def handle_event("save-release", %{"release" => params}, socket) do
    save_release(socket, params)
  end

  # Empties the field rather than saving, so Save changes removes the code
  # and Cancel keeps it, and nothing needs asking in a second dialog.
  @decorate requires_permission(:"deployment_group:release:manage")
  def handle_event("remove-connecting-code", _params, socket) do
    case editing_release(socket) do
      nil ->
        noreply(socket)

      release ->
        params = Map.put(socket.assigns.edit_form.params, "connecting_code", "")

        socket
        |> assign(:edit_form, edit_form(release, params, :validate))
        |> noreply()
    end
  end

  @decorate requires_permission(:"deployment_group:release:manage")
  def handle_event("retry-delta", %{"id" => id}, socket) do
    case find_delta(socket, id) do
      nil ->
        noreply(socket)

      delta ->
        {:ok, _} = Firmwares.retry_firmware_delta(delta)

        socket
        |> refresh_deltas()
        |> send_flash(:info, "Building the delta from #{delta.source.version} again")
        |> noreply()
    end
  end

  # Every group sending the release shares a delta, so deleting one asks
  # first. Opening the dialog checks the same permission as deleting.
  @decorate requires_permission(:"deployment_group:release:manage")
  def handle_event("ask-delete-delta", %{"id" => id}, socket) do
    case find_delta(socket, id) do
      %{status: :completed} = delta -> socket |> assign(:deleting_delta, delta) |> noreply()
      _ -> noreply(socket)
    end
  end

  @decorate requires_membership()
  def handle_event("cancel-delete-delta", _params, socket) do
    socket
    |> assign(:deleting_delta, nil)
    |> noreply()
  end

  @decorate requires_permission(:"deployment_group:release:manage")
  def handle_event("delete-delta", %{"id" => id}, socket) do
    socket = assign(socket, :deleting_delta, nil)

    case find_delta(socket, id) do
      nil ->
        noreply(socket)

      delta ->
        {:ok, _} = Firmwares.delete_firmware_delta(delta)

        socket
        |> refresh_deltas()
        |> send_flash(:info, "Deleted the delta from #{delta.source.version}")
        |> noreply()
    end
  end

  defp save_release(socket, params) do
    %{current_scope: scope} = socket.assigns

    with %DeploymentRelease{} = release <- editing_release(socket),
         {:ok, release} <- ManagedDeployments.update_deployment_release(release, params, scope.user) do
      socket
      |> assign(:releases, ManagedDeployments.list_deployment_releases(socket.assigns.deployment_group))
      |> assign(:editing_id, nil)
      |> assign(:edit_form, nil)
      |> send_flash(:info, "Release #{release.number} saved")
      |> noreply()
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(:edit_form, to_form(changeset, as: :release, action: :update))
        |> noreply()

      _ ->
        socket
        |> send_flash(:error, "The release could not be saved. Please try again.")
        |> noreply()
    end
  end

  defp start_new_release(socket) do
    %{deployment_group: deployment_group} = socket.assigns
    current = deployment_group.current_release

    socket
    |> assign(:firmwares, Firmwares.get_firmwares_for_deployment_group(deployment_group))
    |> assign(:archives, Archives.all_by_product(deployment_group.product))
    |> assign(:show_connecting_code, false)
    |> then(fn socket ->
      # The archive carries over from the current release, since most releases
      # change the firmware alone.
      assign(socket, :new_form, new_release_form(socket, %{"archive" => current && current.archive_id}))
    end)
  end

  defp new_release_form(socket, params, action \\ nil) do
    %{current_scope: scope, deployment_group: deployment_group} = socket.assigns

    firmware = Firmwares.get_by_id(scope.product, params["firmware"])
    archive = Archives.get_by_id(scope.product, params["archive"])

    deployment_group
    |> DeploymentRelease.new_changeset(firmware, archive, params, scope.user)
    |> to_form(action: action)
  end

  defp refresh_firmware_choices(socket, message) do
    if socket.assigns[:open_new_release] && socket.assigns[:new_form] do
      socket
      |> assign(:firmwares, Firmwares.get_firmwares_for_deployment_group(socket.assigns.deployment_group))
      |> send_flash(:notice, message)
    else
      socket
    end
  end

  defp edit_form(release, params, action \\ nil) do
    release
    |> DeploymentRelease.edit_changeset(params)
    |> to_form(as: :release, action: action)
  end

  defp editing_release(socket) do
    socket.assigns.editing_id && Enum.find(socket.assigns.releases, &(&1.id == socket.assigns.editing_id))
  end

  defp find_release(socket, id) do
    Enum.find(socket.assigns.releases, &(to_string(&1.id) == to_string(id)))
  end

  defp find_delta(socket, id) do
    socket.assigns.deltas
    |> Map.values()
    |> List.flatten()
    |> Enum.find(&(to_string(&1.id) == to_string(id)))
  end

  defp refresh_deltas(socket) do
    socket
    |> assign(:delta_counts, ManagedDeployments.release_delta_counts(socket.assigns.deployment_group))
    |> load_deltas()
  end

  # Only the releases devices are headed for have deltas, so only those that
  # are open and counted are looked up.
  defp load_deltas(socket) do
    %{expanded: expanded, releases: releases, delta_counts: counts} = socket.assigns

    deltas =
      releases
      |> Enum.filter(&(MapSet.member?(expanded, &1.id) and Map.has_key?(counts, &1.id)))
      |> Map.new(&{&1.id, ManagedDeployments.release_deltas(&1)})

    socket
    |> assign(:deltas, deltas)
    |> refresh_deleting_delta()
  end

  # The delete dialog closes once the delta it asks about is gone or no
  # longer built, whoever changed it.
  defp refresh_deleting_delta(%{assigns: %{deleting_delta: %{id: id}}} = socket) do
    case find_delta(socket, id) do
      %{status: :completed} = delta -> assign(socket, :deleting_delta, delta)
      _ -> assign(socket, :deleting_delta, nil)
    end
  end

  defp refresh_deleting_delta(socket), do: socket

  # Each release beside when the next one replaced it. The list is newest
  # first, so the newest is replaced by nothing.
  defp rows(releases), do: Enum.zip(releases, [nil | Enum.map(releases, & &1.inserted_at)])

  defp releases_path(scope, deployment_group),
    do: ~p"/org/#{scope.org}/#{scope.product}/deployment_groups/#{deployment_group}/releases"

  defp field_errors(field) do
    if Phoenix.Component.used_input?(field),
      do: Enum.map(field.errors, &CoreComponents.translate_error/1),
      else: []
  end

  defp error?(field), do: field_errors(field) != []

  defp field_id(field, mod) do
    case field.value do
      %Ecto.Association.NotLoaded{} -> nil
      %{__struct__: ^mod, id: id} -> id
      %Ecto.Changeset{data: %{id: id}} -> id
      value when is_binary(value) -> parse_id(value)
      value -> value
    end
  end

  defp parse_id(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp firmware_options(firmwares) do
    firmwares
    |> Enum.sort_by(&parsed_version/1, {:desc, Version})
    |> Enum.map(fn firmware ->
      size = firmware.size && " · #{format_megabytes(firmware.size)}"
      [value: firmware.id, key: "#{firmware.version} · #{String.slice(firmware.uuid, 0..7)}#{size}"]
    end)
  end

  defp archive_options(archives, current) do
    archives
    |> Enum.sort_by(&parsed_version/1, {:desc, Version})
    |> Enum.map(fn archive ->
      sent_with = current && current.archive_id == archive.id && " · the archive #{current.firmware.version} sends"
      [value: archive.id, key: "#{archive.version} · #{String.slice(archive.uuid, 0..7)}#{sent_with || ""}"]
    end)
  end

  defp parsed_version(%{version: version}) do
    case Version.parse(version) do
      {:ok, version} -> version
      :error -> %Version{major: 0, minor: 0, patch: 0}
    end
  end

  defp percent_smaller(%{size: size, target_size: target_size})
       when is_integer(size) and is_integer(target_size) and target_size > 0 do
    round((target_size - size) * 100 / target_size)
  end

  defp percent_smaller(_delta), do: nil

  defp text_length(value) when is_binary(value), do: String.length(value)
  defp text_length(_value), do: 0

  defp description_max(), do: @description_max
  defp notes_max(), do: @notes_max

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp connecting_code_mode_options() do
    [
      [key: "After the group’s code", value: :last],
      [key: "Before the group’s code", value: :first],
      [key: "Instead of the group’s code", value: :override]
    ]
  end

  defp connecting_code_mode_summary(:last), do: "runs after the group’s code"
  defp connecting_code_mode_summary(:first), do: "runs before the group’s code"
  defp connecting_code_mode_summary(:override), do: "runs instead of the group’s code"

  defp send_flash(socket, type, message) do
    send(self(), {:flash, type, message})
    socket
  end
end
