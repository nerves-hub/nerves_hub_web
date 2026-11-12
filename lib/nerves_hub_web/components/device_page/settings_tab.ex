defmodule NervesHubWeb.Components.DevicePage.SettingsTab do
  use NervesHubWeb, tab_component: :settings

  alias NervesHub.Certificate
  alias NervesHub.DeviceLink
  alias NervesHub.Devices
  alias NervesHub.Devices.CACertificates
  alias NervesHub.Devices.Certificates
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Updates
  alias NervesHub.Extensions
  alias NervesHubWeb.Components.CAHelpers
  alias NervesHubWeb.Components.DateTimes
  alias NervesHubWeb.Components.Utils
  alias NervesHubWeb.CoreComponents
  alias Phoenix.HTML.FormField

  def tab_params(_params, _uri, socket) do
    changeset = Ecto.Changeset.change(socket.assigns.device)

    socket
    |> assign(:settings_form, to_form(changeset))
    |> assign(:available_tags, Devices.distinct_tags_for_product(socket.assigns.current_scope.product))
    |> assign(:shared_secrets_enabled, DeviceLink.shared_secrets_enabled?())
    |> assign(:shared_secrets, Devices.list_shared_secret_auths(socket.assigns.device))
    |> assign(:new_shared_secret, nil)
    |> allow_certificate_upload()
    |> cont()
  end

  # Leaving the tab drops the key list, and a new secret not yet dismissed.
  def cleanup(), do: [:shared_secrets, :new_shared_secret]

  # A registered device certificate lets whoever holds its private key connect
  # as the device. Only members who may update the device get an upload
  # configured at all, so LiveView refuses anyone else's upload before any of
  # the file arrives. `handle_progress/3` checks again before saving it.
  defp allow_certificate_upload(socket) do
    if authorized?(:"device:update", socket.assigns.current_scope) do
      allow_upload(socket, :certificate,
        accept: :any,
        auto_upload: true,
        max_entries: 1,
        progress: &handle_progress/3
      )
    else
      socket
    end
  end

  def render(assigns) do
    device = Certificates.preload_device_certificates(assigns.device, force: true)

    # A device certificate names its signer by key id (its AKI, the CA's SKI)
    # rather than by a foreign key, and the signer may never have been
    # registered - so the lookup can come up empty.
    signer_cas = CACertificates.by_ski(device.org_id, Enum.map(device.device_certificates, & &1.aki))

    assigns =
      assigns
      |> Map.put(:device, device)
      |> Map.put(:signer_cas, signer_cas)

    ~H"""
    <div
      id="settings-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content flex w-full flex-col gap-4 p-4 opacity-0 transition-all duration-500 sm:p-6 phx-click-loading:opacity-50"
    >
      <div class="flex w-full flex-col gap-4 lg:flex-row lg:items-start">
        <div class="flex min-w-0 flex-col gap-4 lg:grow lg:basis-0">
          <.form id="settings-form" for={@settings_form} class={card_class()} phx-change="validate-device-settings" phx-submit="update-device-settings">
            <.card_header title="General" />
            <div class="flex flex-col gap-4.5 border-t border-line-subtle p-4">
              <div class="flex flex-col gap-1.5">
                <label for={@settings_form[:description].id} class={field_label_class()}>Description</label>
                <input
                  type="text"
                  id={@settings_form[:description].id}
                  name={@settings_form[:description].name}
                  value={@settings_form[:description].value}
                  placeholder="eg. sensor hub at customer X"
                  phx-debounce="blur"
                  class={[
                    "h-9 w-full bg-surface-raised px-3 text-sm text-content-strong placeholder:text-content-faint max-sm:h-11 max-sm:text-base",
                    control_class(@settings_form[:description])
                  ]}
                />
                <.field_errors field={@settings_form[:description]} />
              </div>

              <div class="flex flex-col gap-1.5">
                <label for="settings-new-tag" class={field_label_class()}>Tags</label>
                <input type="hidden" name={@settings_form[:tags].name} value={@settings_form[:tags].value |> form_tags() |> Enum.join(",")} />
                <div class={[
                  "flex min-h-9 flex-wrap items-center gap-1.5 bg-surface-raised px-1.5 py-1 focus-within:outline focus-within:-outline-offset-1 focus-within:outline-focus-ring max-sm:min-h-11 max-sm:p-1.5",
                  control_class(@settings_form[:tags])
                ]}>
                  <span
                    :for={tag <- form_tags(@settings_form[:tags].value)}
                    data-tag={tag}
                    class="flex h-6 items-center gap-1 rounded border border-line-default bg-surface-muted pr-1 pl-2 text-xs font-medium text-content-body max-sm:h-8 max-sm:pr-0.5 max-sm:text-sm"
                  >
                    {tag}
                    <button
                      type="button"
                      phx-click="settings-remove-tag"
                      phx-value-tag={tag}
                      aria-label={"Remove #{tag}"}
                      class="flex cursor-pointer rounded-sm text-content-faint hover:text-content-strong max-sm:p-1.5"
                    >
                      <span class="lucide-x size-3" aria-hidden="true"></span>
                    </button>
                  </span>
                  <div
                    id="settings-tags-autocomplete"
                    class="relative min-w-24 grow basis-24"
                    phx-hook="TagAutocomplete"
                    data-commit-event="settings-add-tag"
                    data-available-tags={Jason.encode!(@available_tags -- form_tags(@settings_form[:tags].value))}
                  >
                    <input
                      type="text"
                      id="settings-new-tag"
                      name="new_tag"
                      value=""
                      placeholder="Add a tag"
                      autocomplete="off"
                      data-tag-input
                      class="h-6 w-full border-0 bg-transparent p-0 pl-1 text-sm text-content-strong placeholder:text-content-faint focus:ring-0 max-sm:h-8 max-sm:text-base"
                    />
                    <ul
                      id="settings-new-tag-suggestions"
                      phx-update="ignore"
                      data-tag-suggestions
                      role="listbox"
                      hidden
                      class="absolute z-10 mt-1 max-h-56 w-48 overflow-y-auto rounded-md border border-line-default bg-surface-overlay py-1 shadow-overlay"
                    >
                    </ul>
                  </div>
                </div>
                <p class="text-xs text-content-muted">Deployment groups match devices by tag.</p>
                <.field_errors field={@settings_form[:tags]} />
              </div>

              <div class="flex flex-col gap-1.5">
                <div class="flex items-baseline justify-between gap-2">
                  <label for={@settings_form[:connecting_code].id} class={field_label_class()}>First connect code</label>
                  <span class="text-xs text-content-faint">Elixir</span>
                </div>
                <textarea
                  id={@settings_form[:connecting_code].id}
                  name={@settings_form[:connecting_code].name}
                  rows="4"
                  spellcheck="false"
                  phx-debounce="2000"
                  class={[
                    "min-h-18 w-full bg-surface-raised px-3 py-2.5 font-mono text-xs/5 text-content-body max-sm:text-base/6",
                    control_class(@settings_form[:connecting_code])
                  ]}
                ><%= Phoenix.HTML.Form.normalize_value("textarea", @settings_form[:connecting_code].value) %></textarea>
                <p class="text-xs text-content-muted">
                  Runs on the device each time it connects, together with any code its deployment group sets. If it fails, you get a notification.
                </p>
                <.field_errors field={@settings_form[:connecting_code]} />
              </div>
            </div>
            <div
              :if={authorized?(:"device:update", @current_scope)}
              class="flex h-14 shrink-0 items-center justify-end gap-2 border-t border-line-subtle bg-surface-muted px-4 max-sm:h-auto max-sm:py-4"
            >
              <.button style="primary" type="submit" class="max-sm:h-11 max-sm:w-full max-sm:text-sm">Save changes</.button>
            </div>
          </.form>

          <div id="certificates" class={card_class()}>
            <.card_header title="Certificates" subtitle="Used to authenticate the device">
              <:action :if={authorized?(:"device:update", @current_scope)}>
                <form id="upload-certificate" phx-change="validate-cert" phx-drop-target={@uploads.certificate.ref}>
                  <.button type="label" size="sm" for={@uploads.certificate.ref} class="max-sm:h-11 max-sm:w-full max-sm:text-sm">
                    <span class="lucide-upload" aria-hidden="true"></span> Upload certificate
                  </.button>
                  <.live_file_input upload={@uploads.certificate} class="hidden" />
                </form>
              </:action>
            </.card_header>
            <p :if={Enum.empty?(@device.device_certificates)} class="border-t border-line-subtle px-4 py-3.5 text-xs text-content-muted">
              No certificates have been uploaded.
            </p>
            <div :for={certificate <- @device.device_certificates} data-certificate class="flex items-start gap-4 border-t border-line-subtle px-4 py-3.5 max-sm:flex-col max-sm:gap-3">
              <div class="flex min-w-0 grow basis-0 flex-col gap-2">
                <div class="flex items-baseline gap-2">
                  <span class="text-ui/4 text-content-muted">Serial</span>
                  <span class="font-mono text-xs font-medium break-all text-content-strong">{Utils.format_serial(certificate.serial)}</span>
                </div>
                <div class="flex flex-wrap gap-x-5 gap-y-1 text-xs text-content-muted max-sm:flex-col max-sm:text-ui">
                  <span>Signed by <.signer_ca signer_ca={@signer_cas[certificate.aki]} org={@org} /></span>
                  <span>
                    Valid
                    <span class="text-content-body">
                      <.local_datetime at={certificate.not_before} time_zone={@time_zone} format={:medium_date} zone_label={false} /> –
                      <.local_datetime at={certificate.not_after} time_zone={@time_zone} format={:medium_date} zone_label={false} />
                    </span>
                  </span>
                  <span :if={certificate.last_used}>Last used <span class="text-content-body">{DateTimes.from_now(certificate.last_used)}</span></span>
                  <span :if={!certificate.last_used}>Never used</span>
                </div>
              </div>
              <div class="flex shrink-0 gap-1.5">
                <.button
                  type="link"
                  size="sm"
                  square
                  href={~p"/org/#{@org}/#{@product}/devices/#{@device}/certificate/#{certificate}/download"}
                  download
                  aria-label="Download certificate"
                  class="max-sm:size-11"
                >
                  <span class="lucide-download" aria-hidden="true"></span>
                </.button>
                <.button
                  :if={authorized?(:"device:update", @current_scope)}
                  size="sm"
                  square
                  aria-label="Delete certificate"
                  class="max-sm:size-11"
                  phx-click="delete-certificate"
                  phx-value-serial={certificate.serial}
                  data-confirm="Are you sure you want to delete this certificate?"
                >
                  <span class="lucide-trash" aria-hidden="true"></span>
                </.button>
              </div>
            </div>
          </div>

          <div :if={@shared_secrets_enabled} id="shared-secrets" class={card_class()}>
            <.card_header title="Shared secrets" subtitle="For devices that connect without a certificate">
              <:action :if={is_nil(@device.deleted_at) && authorized?(:"device:update", @current_scope)}>
                <.button size="sm" phx-click="create-shared-secret" class="max-sm:h-11 max-sm:w-full max-sm:text-sm">
                  <span class="lucide-plus" aria-hidden="true"></span> Create secret
                </.button>
              </:action>
            </.card_header>
            <div :if={@new_shared_secret} class="flex flex-col items-start gap-3 border-t border-line-subtle bg-warning-soft px-4 py-3.5">
              <p class="text-xs font-medium text-warning-content">
                Copy the secret now. It's only shown once, and can't be retrieved again.
              </p>
              <div class="text-xs text-content-muted">
                Key <code class="font-mono font-medium break-all text-content-strong">{@new_shared_secret.key}</code>
              </div>
              <input type="hidden" id="shared-secret-new" value={@new_shared_secret.secret} />
              <div class="flex gap-2 max-sm:w-full">
                <.button id="shared-secret-new-button" size="sm" value="new" phx-hook="SharedSecretClipboardClick" class="max-sm:h-11 max-sm:flex-1 max-sm:text-sm">
                  <span class="lucide-copy" aria-hidden="true"></span> Copy secret
                </.button>
                <.button size="sm" phx-click="dismiss-shared-secret" class="max-sm:h-11 max-sm:flex-1 max-sm:text-sm">Done</.button>
              </div>
            </div>
            <p :if={Enum.empty?(@shared_secrets)} class="border-t border-line-subtle px-4 py-3.5 text-xs text-content-muted">
              No shared secrets have been created.
            </p>
            <div :if={Enum.any?(@shared_secrets)} class="flex h-8 shrink-0 items-center gap-4 border-t border-line-subtle px-4 text-label font-medium text-content-faint uppercase max-sm:hidden">
              <span class="w-50 shrink-0">Key</span>
              <span class="grow">History</span>
              <span class="w-23 shrink-0"></span>
            </div>
            <%!-- On a phone: the key and its button, then its history under them. --%>
            <div :for={auth <- @shared_secrets} data-shared-secret class="flex min-h-13 items-center gap-4 border-t border-line-subtle px-4 py-2 max-sm:flex-wrap max-sm:gap-y-2 max-sm:py-3">
              <div class="flex w-50 shrink-0 flex-col gap-0.5 max-sm:w-auto max-sm:min-w-0 max-sm:flex-1">
                <code
                  title={auth.key}
                  class={[
                    "truncate font-mono text-xs",
                    if(auth.deactivated_at,
                      do: "text-content-muted line-through decoration-line-strong",
                      else: "font-medium text-content-strong"
                    )
                  ]}
                >
                  {auth.key}
                </code>
                <span :if={auth.last_used} class="text-xs text-content-muted">Last used {DateTimes.from_now(auth.last_used)}</span>
                <span :if={is_nil(auth.last_used)} class="text-xs text-content-faint">Never used</span>
              </div>
              <%!-- The latest change first; a deactivated key keeps who made
                    it on a quieter line underneath. --%>
              <div class="flex min-w-0 grow flex-col gap-0.5 text-xs text-content-muted max-sm:order-last max-sm:basis-full">
                <.shared_secret_change :if={auth.deactivated_at} action="Deactivated" user={auth.deactivated_by} at={auth.deactivated_at} time_zone={@time_zone} />
                <.shared_secret_change
                  action="Created"
                  user={auth.created_by}
                  at={auth.inserted_at}
                  time_zone={@time_zone}
                  class={auth.deactivated_at && "text-content-faint"}
                />
              </div>
              <div class="flex w-23 shrink-0 justify-end max-sm:w-auto">
                <.button
                  :if={is_nil(auth.deactivated_at) && is_nil(@device.deleted_at) && authorized?(:"device:update", @current_scope)}
                  size="sm"
                  class="max-sm:h-10 max-sm:text-sm"
                  phx-click="deactivate-shared-secret"
                  phx-value-key={auth.key}
                  data-confirm="Are you sure you want to deactivate this shared secret? Connections made with it will be closed, and the device can no longer connect with it."
                >
                  Deactivate
                </.button>
                <.badge :if={auth.deactivated_at}>Deactivated</.badge>
              </div>
            </div>
          </div>
        </div>

        <div class="flex min-w-0 flex-col gap-4 lg:grow lg:basis-0">
          <div id="firmware-updates" class={card_class()}>
            <.card_header title="Firmware updates" />
            <div class="flex items-center gap-4 border-t border-line-subtle px-4 py-3.5">
              <div class="flex min-w-0 grow basis-0 flex-col gap-0.5">
                <label for="managed-updates-allowed" class="text-ui/4.5 font-medium text-content-strong">Let the device choose its update mode</label>
                <p class="text-xs text-content-muted">
                  The device may move itself between Automatic and Device managed. The current mode is in the header.
                </p>
              </div>
              <.switch
                id="managed-updates-allowed"
                name="managed-updates-allowed"
                checked={@device.managed_updates_allowed}
                disabled={!authorized?(:"device:toggle-updates", @current_scope)}
                phx-click="toggle-managed-updates-allowed"
              />
            </div>
          </div>

          <div id="extensions" class={card_class()}>
            <.card_header title="Extensions">
              <:aside>{extensions_on(@device)} of {length(available_extensions())} on</:aside>
            </.card_header>
            <div class="flex flex-col px-4 pb-1">
              <div :for={{key, description} <- available_extensions()} data-extension={key} class="flex min-h-13 items-center gap-4 border-t border-line-subtle py-2">
                <div class="flex min-w-0 grow basis-0 flex-col gap-0.5">
                  <label
                    for={"extension-#{key}"}
                    class={["text-ui/4.5 font-medium", if(product_extension?(@device, key), do: "text-content-strong", else: "text-content-muted")]}
                  >
                    {Extensions.display_name(key)}
                  </label>
                  <p class="text-xs text-content-muted">
                    {description}
                    <span :if={!product_extension?(@device, key)}>
                      <span class="font-medium text-content-strong">Off for this product</span>
                      — turn it on in <.link navigate={~p"/org/#{@org}/#{@product}/settings"} class="underline underline-offset-3 hover:text-content-strong">product settings</.link>
                      first.
                    </span>
                  </p>
                </div>
                <.switch
                  id={"extension-#{key}"}
                  name={key}
                  checked={product_extension?(@device, key) and @device.extensions[key] == true}
                  disabled={not product_extension?(@device, key) or !authorized?(:"device:update", @current_scope)}
                  phx-click="update-extension"
                  phx-value-extension={key}
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      <div :if={!@device.deleted_at && authorized?(:"device:update", @current_scope)} id="delete-device" class={[card_class(), "flex-row! flex-wrap items-center gap-4 p-4"]}>
        <div class="flex min-w-0 grow basis-0 flex-col gap-1">
          <h2 class="text-sm/4.5 font-semibold text-content-strong">Delete device</h2>
          <p class="text-xs/4.5 text-content-muted">
            Disconnects the device, removes it from its deployment group and deletes its certificates. It can't connect again until it's restored.
          </p>
        </div>
        <.button
          phx-click="delete-device"
          data-confirm="Are you sure you want to delete this device? It will be disconnected and removed from its deployment group, and any certificates associated with it will be deleted."
          class="text-alert-content! max-sm:h-11 max-sm:w-full max-sm:text-sm *:[[class*=lucide-]]:text-alert-content!"
        >
          <span class="lucide-trash" aria-hidden="true"></span> Delete device…
        </.button>
      </div>

      <div :if={@device.deleted_at && authorized?(:"device:update", @current_scope)} id="deleted-device" class={[card_class(), "flex-row! flex-wrap items-center gap-4 p-4"]}>
        <div class="flex min-w-0 grow basis-0 flex-col gap-1">
          <h2 class="text-sm/4.5 font-semibold text-content-strong">This device is deleted</h2>
          <p class="text-xs/4.5 text-content-muted">
            It can't connect to NervesHub until it's restored. Deleting it permanently removes it for good.
          </p>
        </div>
        <div class="flex shrink-0 gap-2 max-sm:w-full max-sm:flex-col">
          <.button phx-click="restore-device" data-confirm="Are you sure you want to restore this device?" class="max-sm:h-11 max-sm:text-sm">
            <span class="lucide-rotate-ccw" aria-hidden="true"></span> Restore device
          </.button>
          <.button
            phx-click="destroy-device"
            data-confirm="Are you sure you want to permanently delete this device?"
            class="text-alert-content! max-sm:h-11 max-sm:text-sm *:[[class*=lucide-]]:text-alert-content!"
          >
            <span class="lucide-trash" aria-hidden="true"></span> Delete permanently…
          </.button>
        </div>
      </div>
    </div>
    """
  end

  defp card_class(),
    do: "flex w-full flex-col overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card"

  defp field_label_class(), do: "text-ui/4 font-medium text-content-strong"

  defp errors_for(field) do
    if Phoenix.Component.used_input?(field), do: Enum.map(field.errors, &CoreComponents.translate_error/1), else: []
  end

  # The bezel every text control on the page has: a lighter edge, a darker
  # bottom, red when the field has an error.
  defp control_class(field) do
    [
      "rounded border focus:ring-0 focus:outline focus:-outline-offset-1",
      if(errors_for(field) == [],
        do:
          "border-line-control border-b-line-strong focus:border-line-control focus:border-b-line-strong focus:outline-focus-ring",
        else: "border-alert focus:border-alert focus:outline-alert"
      )
    ]
  end

  attr(:field, FormField, required: true)

  defp field_errors(assigns) do
    assigns = assign(assigns, :errors, errors_for(assigns.field))

    ~H"""
    <.error :for={message <- @errors}>{message}</.error>
    """
  end

  # The tags in the form, whether it holds them as the device's list or as the
  # comma-separated text the form sends back.
  defp form_tags(tags) when is_list(tags), do: tags
  defp form_tags(tags) when is_binary(tags), do: split_tags(tags)
  defp form_tags(_tags), do: []

  defp split_tags(text), do: text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)
  slot(:action, doc: "actions at the end of the row")
  slot(:aside, doc: "a quiet note at the end of the row")

  # On a phone the actions leave the header for the foot of the card, across
  # its width: the header turns into its parts, and the actions sort last.
  defp card_header(assigns) do
    ~H"""
    <div class="flex min-h-12 shrink-0 items-center justify-between gap-3 px-4 py-2 max-sm:contents">
      <div class="flex min-w-0 flex-1 items-center justify-between gap-3 max-sm:min-h-12 max-sm:px-4 max-sm:py-2">
        <div class="flex min-w-0 flex-wrap items-baseline gap-x-2">
          <h2 class="text-sm/4.5 font-semibold text-content-strong">{@title}</h2>
          <span :if={@subtitle} class="text-xs text-content-faint">{@subtitle}</span>
        </div>
        <div :if={@aside != []} class="shrink-0 text-xs text-content-faint">{render_slot(@aside)}</div>
      </div>
      <div :if={@action != []} class="flex shrink-0 max-sm:order-last max-sm:border-t max-sm:border-line-subtle max-sm:p-4 max-sm:*:w-full">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:name, :string, required: true)
  attr(:checked, :boolean, required: true)
  attr(:disabled, :boolean, default: false)
  attr(:rest, :global)

  # A checkbox drawn as a switch. It acts as soon as it is flipped, through the
  # `phx-click` it is given, so it needs no form.
  defp switch(assigns) do
    ~H"""
    <span class="relative inline-flex h-4.5 w-8 shrink-0">
      <input
        type="checkbox"
        role="switch"
        id={@id}
        name={@name}
        checked={@checked}
        disabled={@disabled}
        class={[
          "peer size-full cursor-pointer appearance-none rounded-full border-0 bg-line-strong bg-none p-0 text-primary transition-colors light:text-indigo-600",
          "checked:bg-current checked:bg-none focus:ring-0 focus:ring-offset-0",
          "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring",
          "disabled:cursor-not-allowed disabled:opacity-60 [&:disabled:not(:checked)]:bg-line-default"
        ]}
        {@rest}
      />
      <span
        class="pointer-events-none absolute top-0.5 left-0.5 size-3.5 rounded-full bg-white shadow-control transition-transform peer-checked:translate-x-3.5"
        aria-hidden="true"
      ></span>
    </span>
    """
  end

  attr(:signer_ca, :any, required: true)
  attr(:org, :map, required: true)

  defp signer_ca(%{signer_ca: nil} = assigns) do
    ~H"""
    <span class="text-content-body">an unregistered CA</span>
    """
  end

  defp signer_ca(assigns) do
    ~H"""
    <.link navigate={~p"/org/#{@org}/settings/certificates/#{@signer_ca}"} class="text-content-strong underline underline-offset-3 hover:decoration-2">
      {CAHelpers.label(@signer_ca)}
    </.link>
    """
  end

  attr(:action, :string, required: true)
  attr(:user, :any, required: true, doc: "who made the change, or nil when no user did")
  attr(:at, :any, required: true)
  attr(:time_zone, :string, required: true)
  attr(:class, :any, default: nil)

  # "Created by Jane on Oct 30, 2025", or without the name when no one did.
  defp shared_secret_change(assigns) do
    ~H"""
    <span class={@class}>
      {@action}<span :if={@user}> by <span class="text-content-body">{@user.name}</span></span> on <.local_datetime at={@at} time_zone={@time_zone} format={:medium_date} zone_label={false} />
    </span>
    """
  end

  defp product_extension?(device, key), do: device.product.extensions[key] == true

  defp extensions_on(device) do
    Enum.count(available_extensions(), fn {key, _description} ->
      product_extension?(device, key) and device.extensions[key] == true
    end)
  end

  def hooked_event("validate-device-settings", %{"device" => device_params}, socket) do
    changeset = Device.update_changeset(socket.assigns.device, device_params)

    socket
    |> assign(:settings_form, to_form(changeset, action: :validate))
    |> halt()
  end

  def hooked_event("update-device-settings", %{"device" => device_params} = params, socket) do
    authorized!(:"device:update", socket.assigns.current_scope)

    %{device: device, user: user} = socket.assigns

    device_params = with_unadded_tag(device_params, params["new_tag"])

    case Devices.update_device_settings(device, device_params, user) do
      {:ok, device} ->
        socket
        |> assign(:device, device)
        |> assign(:settings_form, to_form(Ecto.Changeset.change(device)))
        |> put_flash(:info, "Device updated.")
        |> halt()

      {:error, %Ecto.Changeset{data: %Device{}} = changeset} ->
        error =
          if Keyword.has_key?(changeset.errors, :deleted_at) do
            "Device cannot be updated because it has been deleted. Please restore the device to make changes."
          else
            "We couldn't save your changes. Please contact support if this happens again."
          end

        socket
        |> put_flash(:error, error)
        |> assign(:settings_form, to_form(changeset))
        |> halt()

      {:error, _} ->
        socket
        |> put_flash(:error, "An unknown error occurred, please contact support.")
        |> halt()
    end
  end

  # Tags are added to and removed from the form, not the device: like the
  # other fields, they are saved with "Save changes".
  def hooked_event("settings-add-tag", %{"tag" => tag}, socket) do
    socket
    |> update_form_tags(&Enum.uniq(&1 ++ split_tags(tag)))
    |> halt()
  end

  def hooked_event("settings-remove-tag", %{"tag" => tag}, socket) do
    socket
    |> update_form_tags(&List.delete(&1, tag))
    |> halt()
  end

  def hooked_event("delete-device", _, socket) do
    authorized!(:"device:delete", socket.assigns.current_scope)

    {:ok, device} = Devices.delete_device(socket.assigns.device)

    send(self(), :reload_device)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "The device has been deleted. This action can be undone.")
    |> halt()
  end

  def hooked_event("restore-device", _, socket) do
    authorized!(:"device:restore", socket.assigns.current_scope)

    {:ok, device} = Devices.restore_device(socket.assigns.device)

    send(self(), :reload_device)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "The device has been restored.")
    |> halt()
  end

  def hooked_event("destroy-device", _, socket) do
    %{current_scope: current_scope, device: device} = socket.assigns

    authorized!(:"device:destroy", current_scope)

    {:ok, _device} = Devices.destroy_device(device)

    send(self(), :reload_device)

    socket
    |> put_flash(:info, "Device permanently destroyed successfully.")
    |> push_navigate(to: ~p"/org/#{current_scope.org}/#{current_scope.product}/devices")
    |> halt()
  end

  # A phx-change handler is required when using live uploads.
  def hooked_event("validate-cert", _, socket), do: {:halt, socket}

  def hooked_event("delete-certificate", %{"serial" => serial}, %{assigns: %{device: device}} = socket) do
    authorized!(:"device:update", socket.assigns.current_scope)

    device = %{device_certificates: certs} = Certificates.preload_device_certificates(device)

    db_cert = Enum.find(certs, &(&1.serial == serial))

    case Certificates.delete_device_certificate(db_cert) do
      {:ok, _db_cert} ->
        updated_certs = Enum.reject(certs, &(&1.serial == serial))

        socket
        |> put_flash(:info, "Certificate deleted.")
        |> assign(device: %{device | device_certificates: updated_certs})
        |> halt()

      _ ->
        socket
        |> put_flash(:error, "Failed to delete certificate, please contact support.")
        |> halt()
    end
  end

  def hooked_event("create-shared-secret", _params, %{assigns: %{device: %{deleted_at: nil} = device}} = socket) do
    authorized!(:"device:update", socket.assigns.current_scope)

    case Devices.issue_shared_secret_auth(device, socket.assigns.user) do
      {:ok, auth} ->
        socket
        |> assign(:new_shared_secret, Map.take(auth, [:key, :secret]))
        |> assign(:shared_secrets, Devices.list_shared_secret_auths(device))
        |> halt()

      {:error, :shared_secrets_not_enabled} ->
        socket
        |> put_flash(:error, "Shared secrets are not enabled on this platform.")
        |> halt()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "We couldn't create a shared secret. Please contact support if this happens again.")
        |> halt()
    end
  end

  def hooked_event("dismiss-shared-secret", _params, socket) do
    socket
    |> assign(:new_shared_secret, nil)
    |> halt()
  end

  def hooked_event(
        "deactivate-shared-secret",
        %{"key" => key},
        %{assigns: %{device: %{deleted_at: nil} = device}} = socket
      ) do
    authorized!(:"device:update", socket.assigns.current_scope)

    socket =
      case Devices.deactivate_shared_secret_auth(device, key, socket.assigns.user) do
        {:ok, _auth} ->
          put_flash(socket, :info, "The shared secret has been deactivated, and connections made with it closed.")

        {:error, :not_found} ->
          put_flash(socket, :error, "That shared secret is no longer active.")
      end

    socket
    |> assign(:shared_secrets, Devices.list_shared_secret_auths(device))
    |> halt()
  end

  def hooked_event(event, _params, socket) when event in ["create-shared-secret", "deactivate-shared-secret"] do
    socket
    |> put_flash(:error, "The device is deleted and must be restored to change its shared secrets.")
    |> halt()
  end

  def hooked_event("toggle-managed-updates-allowed", params, socket) do
    authorized!(:"device:toggle-updates", socket.assigns.current_scope)

    %{device: device, user: user} = socket.assigns
    enabled = params["value"] == "on"

    case Updates.set_managed_updates_allowed(device, enabled, user) do
      {:ok, device} ->
        socket
        |> assign(:device, device)
        |> put_flash(:info, "The device #{(enabled && "may") || "may no longer"} choose its own update mode.")
        |> halt()

      _error ->
        socket
        |> put_flash(:error, "We couldn't save that change. Please contact support if this happens again.")
        |> halt()
    end
  end

  def hooked_event("update-extension", %{"extension" => extension} = params, socket) do
    authorized!(:"device:update", socket.assigns.current_scope)

    value = params["value"]
    available = Extensions.list() |> Enum.map(&to_string/1)

    result =
      case {extension in available, value} do
        {true, "on"} ->
          Devices.enable_extension_setting(socket.assigns.device, extension)

        {true, _} ->
          Devices.disable_extension_setting(socket.assigns.device, extension)
      end

    case result do
      {:ok, _pf} ->
        send(self(), :reload_device)

        put_flash(
          socket,
          :info,
          "The #{Extensions.display_name(extension)} extension was successfully #{(value == "on" && "enabled") || "disabled"}."
        )

      {:error, _changeset} ->
        put_flash(
          socket,
          :error,
          "There was an unexpected error when updating the #{Extensions.display_name(extension)} extension. Please contact support."
        )
    end
    |> halt()
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(_event, socket), do: {:cont, socket}

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  defp update_form_tags(socket, change) do
    %{settings_form: form, device: device} = socket.assigns

    tags = form[:tags].value |> form_tags() |> change.() |> Enum.join(",")
    params = Map.put(form.source.params || %{}, "tags", tags)

    assign(socket, :settings_form, to_form(Device.update_changeset(device, params), action: :validate))
  end

  # A tag typed but not yet added when the form is saved is saved with it,
  # rather than quietly dropped.
  defp with_unadded_tag(device_params, new_tag) when is_binary(new_tag) and new_tag != "" do
    tags = form_tags(device_params["tags"]) ++ split_tags(new_tag)

    Map.put(device_params, "tags", tags |> Enum.uniq() |> Enum.join(","))
  end

  defp with_unadded_tag(device_params, _new_tag), do: device_params

  def handle_progress(:certificate, %{done?: true} = entry, socket) do
    authorized!(:"device:update", socket.assigns.current_scope)

    socket = consume_uploaded_entry(socket, entry, &import_cert(socket, &1.path))

    {:noreply, socket}
  end

  def handle_progress(:certificate, _entry, socket), do: {:noreply, socket}

  defp import_cert(%{assigns: %{device: device}} = socket, path) do
    with {:ok, pem_or_der} <- File.read(path),
         {:ok, otp_cert} <- Certificate.from_pem_or_der(pem_or_der),
         {:ok, _db_cert} <- Certificates.create_device_certificate(device, otp_cert) do
      updated = Certificates.preload_device_certificates(device)

      assign(socket, :device, updated)
      |> put_flash(:info, "Certificate Upload Successful")
      |> ok()
    else
      {:error, :malformed} ->
        {:ok, put_flash(socket, :error, "Incorrect filetype or malformed certificate")}

      {:error, %Ecto.Changeset{errors: errors}} ->
        formatted =
          Enum.map_join(errors, "\n", fn {field, {msg, _}} ->
            ["* ", to_string(field), " ", msg]
          end)

        socket
        |> put_flash(:error, IO.iodata_to_binary(["Failed to save:\n", formatted]))
        |> ok()

      err ->
        socket
        |> put_flash(:error, "Unknown file error - #{inspect(err)}")
        |> ok()
    end
  end

  defp available_extensions() do
    for extension <- Extensions.list(), do: {extension, Extensions.module(extension).description()}
  end
end
