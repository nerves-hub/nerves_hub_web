defmodule NervesHubWeb.Components.DeploymentGroupPage.Settings do
  @moduledoc """
  A deployment group's Settings tab: titled cards in two columns, like a
  product's General settings, drawn from the design system's cards and form
  controls.

  Each card with fields is its own form and saves itself. Changing one brings
  up a bar at its foot with Discard and Save, saying what saving would do
  where that isn't obvious (devices that would leave the group, links that
  stop working). The workflow card acts as soon as a file is picked, and
  removing the workflow or deleting the group asks first.

  The page refreshes every few seconds, so a card with unsaved changes keeps
  them, and only a card without any follows the group as it changes.
  """
  use NervesHubWeb, :live_component

  import NervesHubWeb.Components.Fleet, only: [count_noun: 3]

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHubWeb.Components.DeploymentGroups
  alias NervesHubWeb.Components.Dialog
  alias NervesHubWeb.Components.Switch
  alias NervesHubWeb.CoreComponents
  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS
  # The fields each card's form may change. A card's params are cut down to
  # these, so one card's Save never touches another's fields.
  @cards %{
    general: ~w(name notes),
    matching: ~w(conditions lock_device_membership),
    connecting_code: ~w(connecting_code),
    sending:
      ~w(delta_updatable queue_management concurrent_updates priority_queue_enabled priority_queue_concurrent_updates priority_queue_firmware_version_threshold),
    penalty: ~w(device_failure_threshold device_failure_rate_amount device_failure_rate_seconds penalty_timeout_minutes)
  }

  @titles %{
    general: "General",
    matching: "Device matching",
    connecting_code: "Connecting code",
    sending: "Sending updates",
    penalty: "Penalty box"
  }

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign_new(:confirm, fn -> nil end)
    |> assign_new(:leaving, fn -> nil end)
    |> assign_new(:typed_tag?, fn -> false end)
    |> assign_new(:available_tags, fn -> Devices.distinct_tags_for_product(assigns.current_scope.product) end)
    |> follow_group()
    |> allow_workflow_upload()
    |> ok()
  end

  # Every card without unsaved changes is rebuilt from the group as it is now.
  defp follow_group(socket) do
    forms = Map.get(socket.assigns, :forms, %{})

    forms =
      Map.new(Map.keys(@cards), fn card ->
        case forms[card] do
          %{source: %{changes: changes}} = form when changes != %{} -> {card, form}
          _ -> {card, blank_form(socket.assigns.deployment_group, card)}
        end
      end)

    assign(socket, :forms, forms)
  end

  defp blank_form(deployment_group, card) do
    deployment_group
    |> DeploymentGroup.update_changeset(%{})
    |> to_form(as: card, id: "settings-#{card}")
  end

  # Only a member who may change the group gets an upload configured, so
  # nobody else's browser can send a file at all.
  defp allow_workflow_upload(socket) do
    cond do
      Map.has_key?(socket.assigns[:uploads] || %{}, :workflow_definition) ->
        socket

      authorized?(:"deployment_group:update", socket.assigns.current_scope) ->
        allow_upload(socket, :workflow_definition,
          accept: ~w(.json),
          max_entries: 1,
          auto_upload: true,
          progress: &handle_progress/3
        )

      true ->
        socket
    end
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns =
      assign(assigns,
        can_update?: authorized?(:"deployment_group:update", assigns.current_scope),
        can_toggle_deltas?: authorized?(:"deployment_group:toggle_delta_updates", assigns.current_scope),
        steps: Workflows.definition_steps(assigns.deployment_group.workflow_definition)
      )

    ~H"""
    <div id="deployment-group-settings" class="@container flex flex-col gap-4 p-4 max-sm:gap-3 sm:p-6">
      <p
        :if={!@can_update?}
        id="read-only-notice"
        class="flex items-start gap-2.5 rounded-md bg-surface-muted p-3 text-ui/4.5 text-content-body"
      >
        <span class="mt-px lucide-eye size-4 text-notice" aria-hidden="true"></span>
        <span>You can see these settings, but your role in {@current_scope.org.name} can't change them.</span>
      </p>

      <div class="flex flex-col gap-4 max-sm:gap-3 @4xl:grid @4xl:grid-cols-2 @4xl:items-start">
        <div class="flex min-w-0 flex-col gap-4 max-sm:gap-3">
          <.card_form card={:general} form={@forms.general} can_update?={@can_update?} target={@myself}>
            <.card_header title="General" />
            <.row label="Name" for={@forms.general[:name].id} hint="Shown in lists, Slack and webhooks." errors={errors(@forms.general[:name])}>
              <input
                type="text"
                id={@forms.general[:name].id}
                name={@forms.general[:name].name}
                value={@forms.general[:name].value}
                class={DeploymentGroups.field_class(error?(@forms.general[:name]))}
                phx-debounce="300"
              />
            </.row>
            <.row label="Notes" for={@forms.general[:notes].id} hint="Why the group exists. Shown on its Overview." stacked errors={errors(@forms.general[:notes])}>
              <textarea
                id={@forms.general[:notes].id}
                name={@forms.general[:notes].name}
                rows="3"
                maxlength="1000"
                class={DeploymentGroups.textarea_class(error?(@forms.general[:notes]))}
                phx-debounce="300"
              >{Phoenix.HTML.Form.normalize_value("textarea", @forms.general[:notes].value)}</textarea>
            </.row>
            <:save_note :if={Ecto.Changeset.changed?(@forms.general.source, :name)}>
              Links that use the old name stop working.
            </:save_note>
          </.card_form>

          <.card_form card={:matching} form={@forms.matching} unsaved={@typed_tag?} can_update?={@can_update?} target={@myself}>
            <.card_header title="Device matching" description="A device in no group joins this one when it connects and matches." />
            <.row label="Firmware for" hint="Set by the firmware the group was made with.">
              <span class="font-mono text-ui/8 text-content-strong">
                {@deployment_group.platform} <span class="text-content-faint">·</span> {@deployment_group.architecture}
              </span>
            </.row>
            <.inputs_for :let={conditions} field={@forms.matching[:conditions]}>
              <.row label="Tags" for="settings-matching-new-tag" hint="Leave empty to match any tags." errors={errors(conditions[:tags])}>
                <.tags_field field={conditions[:tags]} available_tags={@available_tags} error={error?(conditions[:tags])} target={@myself} />
                <fieldset class="grid grid-cols-2 gap-0.5 rounded-md border border-line-default bg-surface-muted p-0.5">
                  <legend class="sr-only">A device needs</legend>
                  <label
                    :for={{value, label} <- [{"and", "Require all"}, {"or", "Allow any"}]}
                    class={[
                      "flex cursor-pointer items-center justify-center rounded px-3 py-1.5 text-xs leading-none font-medium whitespace-nowrap text-content-muted",
                      "has-checked:bg-primary has-checked:text-primary-content has-checked:shadow-control light:has-checked:bg-indigo-600",
                      "has-focus-visible:outline-2 has-focus-visible:outline-offset-1 has-focus-visible:outline-focus-ring",
                      "has-disabled:cursor-not-allowed has-disabled:opacity-50"
                    ]}
                  >
                    <input type="radio" name={conditions[:tag_operator].name} value={value} checked={to_string(conditions[:tag_operator].value) == value} class="sr-only" />
                    {label}
                  </label>
                </fieldset>
              </.row>
              <.row label="Firmware version" for={conditions[:version].id} errors={errors(conditions[:version])}>
                <:hint_block>A requirement such as <span class="font-mono">&gt;= 2.0.0</span>. Empty matches any.</:hint_block>
                <input
                  type="text"
                  id={conditions[:version].id}
                  name={conditions[:version].name}
                  value={conditions[:version].value}
                  placeholder="Any version"
                  autocomplete="off"
                  spellcheck="false"
                  class={DeploymentGroups.field_class(error?(conditions[:version]), "font-mono")}
                  phx-debounce="300"
                />
              </.row>
            </.inputs_for>
            <.switch_row form={@forms.matching} field={:lock_device_membership} label="Lock membership" hint="Devices only join or leave when someone moves them." />
            <:save_note>{matching_note(@forms.matching.source, @leaving)}</:save_note>
          </.card_form>

          <.card_form card={:connecting_code} form={@forms.connecting_code} can_update?={@can_update?} target={@myself}>
            <.card_header
              title="Connecting code"
              description="Elixir run in a device’s console when it first connects. A release can run its own before, after or instead of it."
            />
            <div class="flex flex-col gap-2 border-t border-line-default px-4 py-3.5">
              <label for={@forms.connecting_code[:connecting_code].id} class="sr-only">Connecting code</label>
              <textarea
                id={@forms.connecting_code[:connecting_code].id}
                name={@forms.connecting_code[:connecting_code].name}
                rows="5"
                spellcheck="false"
                aria-describedby="settings-connecting-code-hint"
                class={DeploymentGroups.textarea_class(error?(@forms.connecting_code[:connecting_code]), "font-mono")}
                phx-debounce="300"
              >{Phoenix.HTML.Form.normalize_value("textarea", @forms.connecting_code[:connecting_code].value)}</textarea>
              <DeploymentGroups.field_error :for={message <- errors(@forms.connecting_code[:connecting_code])}>{message}</DeploymentGroups.field_error>
              <p id="settings-connecting-code-hint" class="text-xs/4 text-content-muted">Check it compiles: code that crashes takes the console down with it.</p>
            </div>
          </.card_form>
        </div>

        <div class="flex min-w-0 flex-col gap-4 max-sm:gap-3">
          <section id="settings-workflow" class={card_class()}>
            <.card_header title="Workflow" description="The steps each release walks through, uploaded as JSON.">
              <:action :if={@deployment_group.workflow_definition && @can_update?}>
                <.button id="replace-workflow" size="sm" type="label" for={@uploads.workflow_definition.ref}>
                  <span class="lucide-upload" aria-hidden="true"></span> Replace
                </.button>
              </:action>
              <:action :if={!@deployment_group.workflow_definition && @can_update?}>
                <.button id="upload-workflow" size="sm" type="label" for={@uploads.workflow_definition.ref}>
                  <span class="lucide-upload" aria-hidden="true"></span> Upload
                </.button>
              </:action>
            </.card_header>
            <%!-- LiveView reads an upload through its form. --%>
            <form :if={@can_update?} id="workflow-upload-form" phx-change="validate-workflow" phx-target={@myself} class="hidden">
              <.live_file_input upload={@uploads.workflow_definition} />
            </form>

            <p :if={@steps == []} class="border-t border-line-default px-4 py-3.5 text-ui/4.5 text-content-muted">
              No workflow. Each release goes to every device in the group at once, {@deployment_group.concurrent_updates} at a time.
            </p>

            <ol :if={@steps != []} id="workflow-steps" class="border-t border-line-default">
              <li
                :for={step <- @steps}
                class="grid grid-cols-[1.25rem_minmax(0,9rem)_minmax(0,1fr)_auto] items-center gap-x-3 border-b border-line-subtle px-4 py-2.5 text-ui/4.5 last:border-b-0 max-sm:grid-cols-[1.25rem_minmax(0,1fr)_auto]"
              >
                <span class="flex size-5 items-center justify-center rounded-full border border-line-default text-xs text-content-muted tabular-nums">{step.number}</span>
                <span class="truncate font-medium text-content-strong">{DeploymentWorkflowStep.label(step)}</span>
                <span class="text-content-body max-sm:hidden">{step_covers(step)}</span>
                <span class="text-xs whitespace-nowrap text-content-muted">{step_limit(step)}</span>
              </li>
            </ol>

            <div
              :if={@deployment_group.workflow_definition}
              class="flex items-center justify-between gap-4 border-t border-line-default px-4 py-3.5 max-sm:flex-col max-sm:items-stretch max-sm:gap-3"
            >
              <p class="text-xs/4 text-content-muted">A new workflow applies from the next release.</p>
              <div class="flex shrink-0 gap-2 max-sm:*:flex-1">
                <.button size="sm" type="link" href={workflow_download(@deployment_group)} download={"#{@deployment_group.name}-workflow.json"}>
                  <span class="lucide-download" aria-hidden="true"></span> JSON
                </.button>
                <.button :if={@can_update?} size="sm" style="danger" phx-click="confirm-remove-workflow" phx-target={@myself}>
                  Remove workflow
                </.button>
              </div>
            </div>
          </section>

          <.card_form card={:sending} form={@forms.sending} can_update?={@can_update?} target={@myself}>
            <.card_header title="Sending updates" />
            <.switch_row
              form={@forms.sending}
              field={:delta_updatable}
              label="Delta updates"
              hint={
                if @can_toggle_deltas?,
                  do: "Build a delta from the versions devices are on, and send that instead of the full image.",
                  else: "Build a delta from the versions devices are on, and send that instead of the full image. Your role can’t turn this on or off."
              }
              disabled={!@can_toggle_deltas?}
            />
            <.row label="Queue order" for={@forms.sending[:queue_management].id} hint="Which waiting devices update first.">
              <DeploymentGroups.select_control
                id={@forms.sending[:queue_management].id}
                name={@forms.sending[:queue_management].name}
                error={error?(@forms.sending[:queue_management])}
              >
                {Phoenix.HTML.Form.options_for_select([{"Connected longest", "FIFO"}, {"Connected most recently", "LIFO"}], to_string(@forms.sending[:queue_management].value))}
              </DeploymentGroups.select_control>
            </.row>

            <div :if={@deployment_group.workflow_definition} class="mx-4 mb-3 flex items-start gap-2.5 rounded-md bg-surface-muted p-3 text-ui/4.5 text-content-body">
              <span class="mt-px lucide-info size-4 text-notice" aria-hidden="true"></span>
              <span>The workflow sets how many devices update at once in each step, so these aren’t used while the group has one.</span>
            </div>

            <fieldset disabled={@deployment_group.workflow_definition != nil} class="group/paced contents">
              <.row
                label="Devices updating at once"
                for={@forms.sending[:concurrent_updates].id}
                hint="A soft limit: a few more can be updating as devices reconnect."
                errors={errors(@forms.sending[:concurrent_updates])}
              >
                <div class="w-24 self-end max-sm:w-full max-sm:self-auto">
                  <input
                    type="number"
                    min="1"
                    id={@forms.sending[:concurrent_updates].id}
                    name={@forms.sending[:concurrent_updates].name}
                    value={@forms.sending[:concurrent_updates].value}
                    class={DeploymentGroups.field_class(error?(@forms.sending[:concurrent_updates]), "tabular-nums")}
                  />
                </div>
              </.row>
              <.switch_row form={@forms.sending} field={:priority_queue_enabled} label="Priority queue">
                <:hint_block>{priority_queue_hint(@forms.sending)}</:hint_block>
              </.switch_row>
              <div
                :if={Phoenix.HTML.Form.normalize_value("checkbox", @forms.sending[:priority_queue_enabled].value)}
                class="grid grid-cols-2 gap-4 px-4 pb-3 max-sm:grid-cols-1"
              >
                <div class="flex flex-col gap-2">
                  <label for={@forms.sending[:priority_queue_firmware_version_threshold].id} class="text-ui/4 font-medium text-content-body">
                    On this version or older
                  </label>
                  <input
                    type="text"
                    id={@forms.sending[:priority_queue_firmware_version_threshold].id}
                    name={@forms.sending[:priority_queue_firmware_version_threshold].name}
                    value={@forms.sending[:priority_queue_firmware_version_threshold].value}
                    placeholder="1.0.0"
                    autocomplete="off"
                    spellcheck="false"
                    class={DeploymentGroups.field_class(error?(@forms.sending[:priority_queue_firmware_version_threshold]), "font-mono")}
                    phx-debounce="300"
                  />
                  <DeploymentGroups.field_error :for={message <- errors(@forms.sending[:priority_queue_firmware_version_threshold])}>
                    {message}
                  </DeploymentGroups.field_error>
                </div>
                <div class="flex flex-col gap-2">
                  <label for={@forms.sending[:priority_queue_concurrent_updates].id} class="text-ui/4 font-medium text-content-body">At once</label>
                  <input
                    type="number"
                    min="1"
                    id={@forms.sending[:priority_queue_concurrent_updates].id}
                    name={@forms.sending[:priority_queue_concurrent_updates].name}
                    value={@forms.sending[:priority_queue_concurrent_updates].value}
                    class={DeploymentGroups.field_class(error?(@forms.sending[:priority_queue_concurrent_updates]), "tabular-nums")}
                  />
                  <DeploymentGroups.field_error :for={message <- errors(@forms.sending[:priority_queue_concurrent_updates])}>
                    {message}
                  </DeploymentGroups.field_error>
                </div>
              </div>
            </fieldset>
          </.card_form>

          <.card_form card={:penalty} form={@forms.penalty} can_update?={@can_update?} target={@myself}>
            <.card_header
              title="Penalty box"
              description="A device that keeps failing to update stops trying for a while. Turning updates back on from its page lets it out early."
            />
            <.penalty_row label="After this many failed attempts" errors={errors(@forms.penalty[:device_failure_threshold])}>
              <.number_input field={@forms.penalty[:device_failure_threshold]} label="After this many failed attempts" />
              <span>in total</span>
            </.penalty_row>
            <.penalty_row
              label="Or this many close together"
              errors={errors(@forms.penalty[:device_failure_rate_amount]) ++ errors(@forms.penalty[:device_failure_rate_seconds])}
            >
              <.number_input field={@forms.penalty[:device_failure_rate_amount]} label="Or this many close together" />
              <span>in</span>
              <.number_input field={@forms.penalty[:device_failure_rate_seconds]} label="Within seconds" />
              <span>sec</span>
            </.penalty_row>
            <.penalty_row label="It stays in the penalty box for" errors={errors(@forms.penalty[:penalty_timeout_minutes])}>
              <.number_input field={@forms.penalty[:penalty_timeout_minutes]} label="It stays in the penalty box for" />
              <span>minutes</span>
            </.penalty_row>
          </.card_form>
        </div>
      </div>

      <section
        :if={authorized?(:"deployment_group:delete", @current_scope)}
        id="settings-delete"
        class={[card_class(), "flex-row! items-center justify-between gap-6 p-4 max-sm:flex-col! max-sm:items-stretch max-sm:gap-3"]}
      >
        <div class="flex min-w-0 flex-col gap-1">
          <h2 class="text-group-title text-content-strong">Delete {@deployment_group.name}</h2>
          <p class="text-ui/4.5 text-content-muted">{delete_consequence(@device_count)} Its releases go with it. This can’t be undone.</p>
        </div>
        <.button style="danger" class="shrink-0" phx-click="confirm-delete" phx-target={@myself}>Delete group</.button>
      </section>

      <.confirm_dialog :if={@confirm} confirm={@confirm} deployment_group={@deployment_group} device_count={@device_count} target={@myself} />
    </div>
    """
  end

  defp card_class(),
    do: "flex w-full flex-col overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card"

  attr(:card, :atom, required: true)
  attr(:form, Form, required: true)
  attr(:unsaved, :boolean, default: false, doc: "something to save that the changeset doesn't hold yet")
  attr(:can_update?, :boolean, required: true)
  attr(:target, :any, required: true)
  slot(:inner_block, required: true)
  slot(:save_note, doc: "what saving would do, in place of “Unsaved changes”")

  # A card that is its own form, with the save bar at its foot while it has
  # unsaved changes. A member who can't change the group sees every field
  # disabled.
  defp card_form(assigns) do
    assigns =
      assign(assigns,
        dirty?: assigns.unsaved or assigns.form.source.changes != %{},
        note: List.first(assigns.save_note)
      )

    ~H"""
    <.form for={@form} id={"settings-#{@card}-form"} phx-change="validate" phx-submit="save" phx-target={@target} class={card_class()}>
      <fieldset disabled={!@can_update?} class="contents">
        {render_slot(@inner_block)}
      </fieldset>
      <div
        :if={@dirty?}
        id={"settings-#{@card}-save"}
        class="flex items-center justify-between gap-4 border-t border-line-default bg-surface-muted px-4 py-3 max-sm:flex-col max-sm:items-stretch"
      >
        <p class="text-ui/4.5 text-content-body">
          <%= if @note do %>
            {render_slot(@note)}
          <% else %>
            Unsaved changes
          <% end %>
        </p>
        <div class="flex shrink-0 gap-2 max-sm:*:flex-1">
          <.button phx-click="discard" phx-value-card={@card} phx-target={@target}>Discard</.button>
          <.button style="primary" type="submit">Save</.button>
        </div>
      </div>
    </.form>
    """
  end

  attr(:title, :string, required: true)
  attr(:description, :string, default: nil)
  slot(:action, doc: "the card's one action, a small button")

  # The card's title and what it's for, as product settings' cards draw them.
  # The rows under it each draw their own top rule.
  defp card_header(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-6 px-4 py-3.5 max-sm:flex-col max-sm:items-stretch max-sm:gap-3">
      <div class="flex min-w-0 flex-col gap-0.5">
        <h2 class="text-sm/5 font-semibold text-content-strong">{@title}</h2>
        <p :if={@description} class="text-ui/4.5 text-content-muted">{@description}</p>
      </div>
      <div :for={action <- @action} class="flex shrink-0 max-sm:*:w-full">{render_slot(action)}</div>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:for, :string, default: nil)
  attr(:hint, :string, default: nil)
  attr(:stacked, :boolean, default: false, doc: "the control under the text, for a textarea")
  attr(:errors, :list, default: [])
  slot(:hint_block, doc: "the hint, when it needs markup")
  slot(:inner_block, required: true)

  # A setting's name and what to know about it, with its control at the end
  # of the row, or under it when it's stacked or on a phone.
  defp row(assigns) do
    ~H"""
    <div class={[
      "flex gap-x-6 gap-y-2 border-t border-line-default px-4 py-3.5",
      if(@stacked, do: "flex-col", else: "items-start justify-between max-sm:flex-col max-sm:items-stretch")
    ]}>
      <div class={["flex min-w-0 flex-col gap-1", !@stacked && "sm:pt-1.5"]}>
        <label :if={@for} for={@for} class="text-sm/5 font-medium text-content-strong group-disabled/paced:text-content-muted">{@label}</label>
        <span :if={!@for} class="text-sm/5 font-medium text-content-strong">{@label}</span>
        <span :if={@hint || @hint_block != []} class="text-ui/4.5 text-content-muted">{@hint}{render_slot(@hint_block)}</span>
      </div>
      <div class={["flex flex-col gap-2", !@stacked && "w-60 shrink-0 max-sm:w-full"]}>
        {render_slot(@inner_block)}
        <DeploymentGroups.field_error :for={message <- @errors}>{message}</DeploymentGroups.field_error>
      </div>
    </div>
    """
  end

  attr(:field, FormField, required: true)
  attr(:available_tags, :list, required: true)
  attr(:error, :boolean, required: true)
  attr(:target, :any, required: true)

  # The tags as removable chips in a field, with an input after them that adds
  # one on Enter or a comma, offering the product's other tags as it's typed
  # (the `TagAutocomplete` hook), as the device page's Settings tab has them.
  # The tags go back in a hidden input, so they save with the rest of the card.
  defp tags_field(assigns) do
    assigns = assign(assigns, :tags, tags_list(assigns.field.value))

    ~H"""
    <div class={[
      "flex min-h-8 flex-wrap items-center gap-1 rounded border bg-surface-raised px-1 py-0.75 focus-within:ring-3 max-sm:min-h-10 max-sm:rounded-md",
      "has-disabled:border-line-default has-disabled:bg-surface-muted",
      if(@error,
        do: "border-alert focus-within:ring-alert/20",
        else: "border-line-control border-b-line-strong focus-within:border-primary focus-within:ring-primary/20"
      )
    ]}>
      <input type="hidden" name={@field.name} value={Enum.join(@tags, ",")} />
      <span
        :for={tag <- @tags}
        data-tag={tag}
        class="flex h-6 items-center gap-1 rounded border border-line-default bg-surface-muted pr-1 pl-2 text-xs font-medium text-content-body max-sm:h-8 max-sm:pr-0.5 max-sm:text-sm"
      >
        {tag}
        <button
          type="button"
          phx-click="remove-tag"
          phx-value-tag={tag}
          phx-target={@target}
          aria-label={"Remove #{tag}"}
          class="flex cursor-pointer rounded-sm text-content-faint hover:text-content-strong disabled:hidden max-sm:p-1.5"
        >
          <span class="lucide-x--bold size-3" aria-hidden="true"></span>
        </button>
      </span>
      <div
        id="settings-matching-tags"
        class="relative min-w-24 grow basis-24"
        phx-hook="TagAutocomplete"
        phx-target={@target}
        data-commit-event="add-tag"
        data-available-tags={Jason.encode!(@available_tags -- @tags)}
      >
        <input
          type="text"
          id="settings-matching-new-tag"
          name="new_tag"
          value=""
          placeholder="Add a tag"
          autocomplete="off"
          data-tag-input
          class="h-6 w-full border-0 bg-transparent p-0 pl-1 text-ui text-content-strong placeholder:text-content-faint focus:ring-0 focus:outline-none max-sm:h-8 max-sm:text-sm"
        />
        <ul
          id="settings-matching-tag-suggestions"
          phx-update="ignore"
          data-tag-suggestions
          role="listbox"
          hidden
          class="absolute z-10 mt-1 max-h-56 w-48 overflow-y-auto rounded-md border border-line-default bg-surface-overlay py-1 shadow-overlay"
        >
        </ul>
      </div>
    </div>
    """
  end

  attr(:form, Form, required: true)
  attr(:field, :atom, required: true)
  attr(:label, :string, required: true)
  attr(:hint, :string, default: nil)
  attr(:disabled, :boolean, default: false, doc: "for a member whose role can't change this one field")
  slot(:hint_block, doc: "the hint, when it is worked out from the form")

  # A switch in a form: the hidden "false" goes when it's off. A disabled one
  # sends nothing, its hidden "false" included.
  defp switch_row(assigns) do
    assigns = assign(assigns, :field, assigns.form[assigns.field])

    ~H"""
    <div class="flex items-center justify-between gap-6 border-t border-line-default px-4 py-3.5">
      <div class="flex min-w-0 flex-col gap-1">
        <label
          for={@field.id}
          class={[
            "text-sm/5 font-medium group-disabled/paced:cursor-not-allowed group-disabled/paced:text-content-muted",
            if(@disabled, do: "cursor-not-allowed text-content-muted", else: "cursor-pointer text-content-strong")
          ]}
        >
          {@label}
        </label>
        <span :if={@hint} id={"#{@field.id}-hint"} class="text-ui/4.5 text-content-muted">{@hint}</span>
        <span :for={hint <- @hint_block} id={"#{@field.id}-hint"} class="text-ui/4.5 text-content-muted">{render_slot(hint)}</span>
      </div>
      <input type="hidden" name={@field.name} value="false" disabled={@disabled} />
      <Switch.switch
        id={@field.id}
        name={@field.name}
        value="true"
        checked={Phoenix.HTML.Form.normalize_value("checkbox", @field.value)}
        disabled={@disabled}
        aria-describedby={"#{@field.id}-hint"}
      />
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:errors, :list, default: [])
  slot(:inner_block, required: true)

  defp penalty_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-x-6 gap-y-2 border-t border-line-default px-4 py-3.5 max-sm:flex-col max-sm:items-stretch">
      <span class="text-sm/5 font-medium text-content-strong" aria-hidden="true">{@label}</span>
      <div class="flex flex-col gap-2">
        <div class="flex items-center gap-2 text-ui whitespace-nowrap text-content-muted">{render_slot(@inner_block)}</div>
        <DeploymentGroups.field_error :for={message <- @errors}>{message}</DeploymentGroups.field_error>
      </div>
    </div>
    """
  end

  attr(:field, FormField, required: true)
  attr(:label, :string, required: true)

  defp number_input(assigns) do
    ~H"""
    <label for={@field.id} class="sr-only">{@label}</label>
    <div class="w-20 shrink-0">
      <input type="number" min="1" id={@field.id} name={@field.name} value={@field.value} class={DeploymentGroups.field_class(error?(@field), "tabular-nums")} />
    </div>
    """
  end

  attr(:confirm, :atom, required: true)
  attr(:deployment_group, DeploymentGroup, required: true)
  attr(:device_count, :integer, required: true)
  attr(:target, :any, required: true)

  defp confirm_dialog(%{confirm: :remove_workflow} = assigns) do
    ~H"""
    <Dialog.confirm id="settings-confirm" title="Remove the workflow?" on_cancel={JS.push("cancel-confirm", target: @target)}>
      <p>Releases made from now on go to every device in the group at once. A release already walking through its steps carries on with them.</p>
      <:actions>
        <.button style="danger-solid" phx-click="remove-workflow" phx-target={@target}>Remove workflow</.button>
      </:actions>
    </Dialog.confirm>
    """
  end

  defp confirm_dialog(%{confirm: :delete} = assigns) do
    ~H"""
    <Dialog.confirm id="settings-confirm" title={"Delete #{@deployment_group.name}?"} on_cancel={JS.push("cancel-confirm", target: @target)}>
      <p>{delete_consequence(@device_count)} Its releases go with it. This can’t be undone.</p>
      <:actions>
        <%!-- The page deletes the group, since it navigates away afterwards. --%>
        <.button style="danger-solid" phx-click="delete">Delete {@deployment_group.name}</.button>
      </:actions>
    </Dialog.confirm>
    """
  end

  defp delete_consequence(0), do: "No devices are in it."

  defp delete_consequence(1), do: "Its 1 device leaves it, and joins another group it matches when it next connects."

  defp delete_consequence(count) do
    "Its #{count_noun(count, "device", "devices")} leave it, and join another group they match when they next connect."
  end

  # What saving the Device matching card does to the devices already in it.
  # Only a version requirement moves them, and only while membership is
  # unlocked; tags decide which devices join.
  defp matching_note(changeset, leaving) do
    locked? = Ecto.Changeset.get_field(changeset, :lock_device_membership)
    version = Ecto.Changeset.get_field(changeset, :conditions).version

    cond do
      locked? ->
        "Devices already in the group stay in it."

      leaving in [nil, 0] ->
        "Devices already in the group stay. These decide which devices join it."

      leaving == 1 ->
        "1 device in the group doesn’t meet #{version}, and leaves it when it next connects."

      true ->
        "#{count_noun(leaving, "device", "devices")} in the group don’t meet #{version}, and leave it when they next connect."
    end
  end

  defp priority_queue_hint(form) do
    threshold = form[:priority_queue_firmware_version_threshold].value
    at_once = form[:priority_queue_concurrent_updates].value

    if Form.normalize_value("checkbox", form[:priority_queue_enabled].value) and threshold not in [nil, ""] do
      "Devices on #{threshold} or older skip the queue, #{at_once} at a time."
    else
      "Lets devices on old firmware, such as ones fresh from the factory, skip the queue."
    end
  end

  # Which devices a workflow step takes, and what holds it up.
  defp step_covers(%{type: :approval_required}), do: "Someone approves before it goes on"
  defp step_covers(%{type: :catch_all}), do: "Everything else that matches"

  defp step_covers(%{matching_conditions: conditions}) do
    conditions = conditions || %{tags: [], network_interfaces: [], match_limit: nil}

    [
      conditions.match_limit && "Up to #{count_noun(conditions.match_limit, "device", "devices")}",
      conditions.tags != [] && "tagged #{Enum.join(conditions.tags, ", ")}",
      conditions.network_interfaces not in [nil, []] && "on #{Enum.join(conditions.network_interfaces, " or ")}"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
    |> DeploymentGroups.upcase_first()
  end

  defp step_limit(%{type: :approval_required}), do: "Approval"
  defp step_limit(%{type: :catch_all, concurrency: at_once}), do: "#{at_once} at a time"

  defp step_limit(%{failure_tolerance: %{devices: n}}) when is_integer(n),
    do: "Stops after #{count_noun(n, "failure", "failures")}"

  defp step_limit(%{failure_tolerance: %{percent: percent}}) when is_integer(percent),
    do: "Stops after #{percent}% fail"

  defp step_limit(_step), do: ""

  # The definition as a file to save, without a round trip: a `download`
  # link to a data URL, which <.link> takes as a {scheme, rest} pair.
  defp workflow_download(%{workflow_definition: definition}) do
    {:data,
     "application/json;charset=utf-8," <> URI.encode(Jason.encode!(definition, pretty: true), &URI.char_unreserved?/1)}
  end

  defp errors(field) do
    if Phoenix.Component.used_input?(field),
      do: Enum.map(field.errors, &CoreComponents.translate_error/1),
      else: []
  end

  defp error?(field), do: errors(field) != []

  # The form holds tags as the group's list, or as the text it sent back.
  defp tags_list(tags) when is_list(tags), do: tags
  defp tags_list(tags) when is_binary(tags), do: split_tags(tags)
  defp tags_list(_tags), do: []

  defp split_tags(text), do: text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  # Adds or removes a tag in the Device matching card's form, keeping the rest
  # of what it holds. The tags come from what the form last sent, so a tag the
  # changeset refused stays on show with its error.
  defp change_tags(socket, change) do
    %{deployment_group: deployment_group, forms: %{matching: form}} = socket.assigns
    params = form.source.params || %{}
    conditions = Map.get(params, "conditions", %{})

    tags =
      case conditions do
        %{"tags" => tags} when is_binary(tags) -> split_tags(tags)
        _ -> Ecto.Changeset.get_field(form.source, :conditions).tags
      end

    params = Map.put(params, "conditions", Map.put(conditions, "tags", tags |> change.() |> Enum.join(",")))

    assign_form(socket, :matching, DeploymentGroup.update_changeset(deployment_group, params), :validate)
  end

  # A tag typed but not added when the card is saved is saved with it.
  defp with_unadded_tag(%{"conditions" => %{"tags" => tags}} = card_params, new_tag)
       when is_binary(tags) and is_binary(new_tag) do
    case split_tags(new_tag) do
      [] -> card_params
      added -> put_in(card_params, ["conditions", "tags"], Enum.join(Enum.uniq(split_tags(tags) ++ added), ","))
    end
  end

  defp with_unadded_tag(card_params, _new_tag), do: card_params

  # Turning delta updates on or off is a permission of its own, as it is for
  # the API, so a member without it can save the rest of the card but not that.
  defp keep_permitted(card_params, scope) do
    if authorized?(:"deployment_group:toggle_delta_updates", scope),
      do: card_params,
      else: Map.delete(card_params, "delta_updatable")
  end

  # The card a form's params come from, and those params cut down to its
  # fields.
  defp card_params(params) do
    Enum.find_value(@cards, fn {card, fields} ->
      case params[Atom.to_string(card)] do
        %{} = card_params -> {card, Map.take(card_params, fields)}
        _ -> nil
      end
    end)
  end

  defp assign_form(socket, card, changeset, action) do
    socket
    |> update(:forms, &Map.put(&1, card, to_form(changeset, as: card, id: "settings-#{card}", action: action)))
    |> then(fn socket -> if card == :matching, do: assign_leaving(socket, changeset), else: socket end)
  end

  # How many devices a new version requirement would send out of the group.
  defp assign_leaving(socket, changeset) do
    conditions = Ecto.Changeset.get_change(changeset, :conditions)

    leaving =
      if (changeset.valid? and conditions) && Ecto.Changeset.changed?(conditions, :version) do
        ManagedDeployments.count_version_mismatches(
          socket.assigns.deployment_group,
          Ecto.Changeset.get_field(conditions, :version)
        )
      end

    assign(socket, :leaving, leaving)
  end

  @impl Phoenix.LiveComponent
  @decorate requires_membership()
  def handle_event("validate", params, socket) do
    case card_params(params) do
      {card, card_params} ->
        changeset = DeploymentGroup.update_changeset(socket.assigns.deployment_group, card_params)

        socket
        |> assign_form(card, changeset, :validate)
        |> then(
          &if(card == :matching, do: assign(&1, :typed_tag?, split_tags(params["new_tag"] || "") != []), else: &1)
        )
        |> noreply()

      nil ->
        noreply(socket)
    end
  end

  @decorate requires_membership()
  def handle_event("add-tag", %{"tag" => tag}, socket) do
    socket
    |> change_tags(&Enum.uniq(&1 ++ split_tags(tag)))
    |> assign(:typed_tag?, false)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("remove-tag", %{"tag" => tag}, socket) do
    socket
    |> change_tags(&List.delete(&1, tag))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("discard", %{"card" => name}, socket) do
    case Enum.find(Map.keys(@cards), &(Atom.to_string(&1) == name)) do
      nil ->
        noreply(socket)

      card ->
        socket
        |> update(:forms, &Map.put(&1, card, blank_form(socket.assigns.deployment_group, card)))
        |> then(&if(card == :matching, do: assign(&1, :typed_tag?, false), else: &1))
        |> noreply()
    end
  end

  @decorate requires_permission(:"deployment_group:update")
  def handle_event("save", params, socket) do
    %{current_scope: %{org: org, product: product, user: user}, deployment_group: deployment_group} = socket.assigns
    %{name: old_name} = deployment_group
    {card, card_params} = card_params(params)

    card_params =
      card_params
      |> with_unadded_tag(params["new_tag"])
      |> keep_permitted(socket.assigns.current_scope)

    case ManagedDeployments.update_deployment_group(deployment_group, card_params, user) do
      {:ok, %{name: name} = updated} when name != old_name ->
        :ok = AuditLogs.audit!(user, updated, "User #{user.name} updated deployment group #{updated.name}")

        # The page's address is the group's name, so it moves with it.
        socket
        |> put_flash(:info, "#{@titles[card]} saved")
        |> push_navigate(to: ~p"/org/#{org}/#{product}/deployment_groups/#{updated}/settings")
        |> noreply()

      {:ok, updated} ->
        :ok = AuditLogs.audit!(user, updated, "User #{user.name} updated deployment group #{updated.name}")

        socket
        |> assign(:deployment_group, updated)
        |> update(:forms, &Map.put(&1, card, blank_form(updated, card)))
        |> then(&if(card == :matching, do: assign(&1, :typed_tag?, false), else: &1))
        |> flash(:info, "#{@titles[card]} saved")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign_form(card, changeset, :update)
        |> noreply()
    end
  end

  # The file goes up as soon as it's picked; `handle_progress/3` takes it from
  # there.
  @decorate requires_membership()
  def handle_event("validate-workflow", _params, socket), do: noreply(socket)

  @decorate requires_permission(:"deployment_group:update")
  def handle_event("confirm-remove-workflow", _params, socket) do
    socket
    |> assign(:confirm, :remove_workflow)
    |> noreply()
  end

  @decorate requires_permission(:"deployment_group:delete")
  def handle_event("confirm-delete", _params, socket) do
    socket
    |> assign(:confirm, :delete)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("cancel-confirm", _params, socket) do
    socket
    |> assign(:confirm, nil)
    |> noreply()
  end

  @decorate requires_permission(:"deployment_group:update")
  def handle_event("remove-workflow", _params, socket) do
    %{current_scope: %{user: user}, deployment_group: deployment_group} = socket.assigns

    case ManagedDeployments.update_deployment_group(deployment_group, %{workflow_definition: nil}, user) do
      {:ok, updated} ->
        :ok =
          AuditLogs.audit!(
            user,
            updated,
            "User #{user.name} removed the Workflow Definition from the deployment group #{updated.name}"
          )

        socket
        |> assign(deployment_group: updated, confirm: nil)
        |> flash(:info, "Workflow removed. Releases made from now on go to every device at once.")
        |> noreply()

      {:error, _changeset} ->
        socket
        |> assign(:confirm, nil)
        |> flash(:error, "The workflow couldn’t be removed. Try again, and contact support if it keeps happening.")
        |> noreply()
    end
  end

  @decorate requires_permission(:"deployment_group:update")
  def handle_progress(:workflow_definition, entry, socket) do
    if entry.done? do
      [contents] =
        consume_uploaded_entries(socket, :workflow_definition, fn %{path: path}, _entry ->
          {:ok, File.read!(path)}
        end)

      # The file is whatever someone picked, so a decode failure is an ordinary
      # outcome to report rather than something to crash the page over.
      case JSON.decode(contents) do
        {:ok, workflow_definition} ->
          save_workflow_definition(socket, workflow_definition)

        {:error, _reason} ->
          socket
          |> flash(:error, "That file could not be read as JSON. Check it for a stray comma or bracket.")
          |> noreply()
      end
    else
      noreply(socket)
    end
  end

  defp save_workflow_definition(socket, workflow_definition) do
    %{current_scope: %{user: user}, deployment_group: deployment_group} = socket.assigns

    params = %{workflow_definition: workflow_definition}

    case ManagedDeployments.update_deployment_group(deployment_group, params, user) do
      {:ok, updated} ->
        :ok =
          AuditLogs.audit!(
            user,
            updated,
            "User #{user.name} uploaded a new Workflow definition to the deployment group #{updated.name}"
          )

        socket
        |> assign(:deployment_group, updated)
        |> flash(:info, "Workflow saved. It applies from the next release.")
        |> noreply()

      {:error, changeset} ->
        socket
        |> flash(:error, workflow_definition_error_message(changeset))
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

  # A flash put on a live component's own socket only ever reaches the page
  # because a navigation carries it into the next mount. Anything that stays put
  # has to ask the LiveView to raise it, which is what the other tabs do.
  defp flash(socket, level, message) do
    send(self(), {:flash, level, message})

    socket
  end
end
