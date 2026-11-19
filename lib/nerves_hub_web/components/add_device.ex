defmodule NervesHubWeb.Components.AddDevice do
  @moduledoc """
  The Add device dialog over a product's devices list, at `/devices/new`.

  Devices add themselves the first time they connect, so adding one here sets
  it up ahead of that: its description, tags and first connect code, and the
  credentials it will connect with. One with the product's shared secret, or
  a certificate one of the org's CAs signed, needs nothing more: it's matched
  by its identifier when it connects. One given a shared secret of its own
  gets the secret here, shown once, and the dialog stays open on it until it
  is closed on purpose. One with a certificate nothing signed has it uploaded.

  The list (`NervesHubWeb.Live.Devices.Index`) owns the URL: closing the
  dialog patches back to it. When a device given its own secret is added, the
  component sends the list `{__MODULE__, {:added, device}}` so it can show the
  device and watch for it to connect; the list reports the connection with
  `send_update(..., connected: true)`.
  """
  use NervesHubWeb, :live_component

  alias NervesHub.Certificate
  alias NervesHub.DeviceLink
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments
  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  # Groups named in the "these tags match" line before it counts the rest.
  @named_groups 2

  @impl Phoenix.LiveComponent
  def update(%{connected: true}, socket) do
    socket
    |> assign(:connected?, true)
    |> ok()
  end

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> init()
    |> ok()
  end

  defp init(%{assigns: %{form: _}} = socket), do: socket

  defp init(socket) do
    connections = connections(socket.assigns.product)

    socket
    |> assign(:connections, connections)
    |> assign(:connection, hd(connections))
    |> allow_upload(:certificate, accept: :any, max_entries: 1, max_file_size: 64_000)
    |> reset()
  end

  defp reset(socket) do
    socket
    |> assign(:added, nil)
    |> assign(:connected?, false)
    |> assign(:certificate_error, nil)
    |> assign(:matching_groups, [])
    |> assign(:matched_tags, [])
    |> assign_form(%{}, nil)
  end

  # How a device can connect here, the default first. Shared secrets are off
  # on some instances, and a product only offers its own when it has one.
  defp connections(product) do
    secrets? = DeviceLink.shared_secrets_enabled?()
    product_secret? = Enum.any?(product.shared_secret_auths, &is_nil(&1.deactivated_at))

    Enum.filter(["product", "own", "certificate"], fn
      "product" -> secrets? and product_secret?
      "own" -> secrets?
      "certificate" -> true
    end)
  end

  @decorate requires_membership()
  @impl Phoenix.LiveComponent
  def handle_event("validate", %{"device" => device_params} = params, socket) do
    socket
    |> assign_connection(params["connection"])
    |> assign_form(device_params, :validate)
    |> noreply()
  end

  # Tags are added to and removed from the form, as on the device's Settings
  # tab: the tag field only holds the one being typed.
  @decorate requires_membership()
  def handle_event("add-tag", %{"tag" => tag}, socket) do
    socket
    |> update_form_tags(&Enum.uniq(&1 ++ split_tags(tag)))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("remove-tag", %{"tag" => tag}, socket) do
    socket
    |> update_form_tags(&List.delete(&1, tag))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("cancel-certificate", %{"ref" => ref}, socket) do
    socket
    |> cancel_upload(:certificate, ref)
    |> assign(:certificate_error, nil)
    |> noreply()
  end

  # Giving a device its own secret or certificate is part of adding it, as it
  # is through the API: a member who can add a device chooses how it connects.
  @decorate requires_permission(:"device:create")
  def handle_event("save", %{"device" => device_params} = params, socket) do
    device_params = with_unadded_tag(device_params, params["new_tag"])
    socket = assign_connection(socket, params["connection"])
    changeset = Device.create_changeset(socket.assigns.product, device_params)

    if changeset.valid? do
      socket
      |> create(socket.assigns.connection, device_params)
      |> noreply()
    else
      socket
      |> assign_form(device_params, :insert)
      |> noreply()
    end
  end

  @decorate requires_membership()
  def handle_event("add-another", _params, socket) do
    socket
    |> reset()
    |> noreply()
  end

  defp create(socket, "own", params) do
    %{product: product, current_scope: scope} = socket.assigns

    case Devices.create_device_with_shared_secret_auth(product, params, scope.user) do
      {:ok, {device, auth}} ->
        send(self(), {__MODULE__, {:added, device}})

        socket
        |> assign(:added, %{device: device, key: auth.key, secret: auth.secret})
        |> assign(:connected?, false)

      error ->
        creation_failed(socket, params, error)
    end
  end

  defp create(socket, "certificate", params) do
    case uploaded_certificate(socket) do
      :none ->
        create(socket, "product", params)

      {:ok, otp_cert} ->
        %{product: product, current_scope: scope} = socket.assigns

        case Devices.create_device_with_certificate(product, params, scope.user, otp_cert) do
          {:ok, device} ->
            [nil] = consume_uploaded_entries(socket, :certificate, fn _meta, _entry -> {:ok, nil} end)
            added(socket, device)

          error ->
            creation_failed(socket, params, error)
        end

      {:error, message} ->
        socket
        |> assign_form(params, :insert)
        |> assign(:certificate_error, message)
    end
  end

  defp create(socket, _connection, params) do
    %{product: product, current_scope: scope} = socket.assigns

    case Devices.create_device(product, params, scope.user, []) do
      {:ok, device} -> added(socket, device)
      error -> creation_failed(socket, params, error)
    end
  end

  defp added(socket, device) do
    socket
    |> put_flash(:info, "Added #{device.identifier}.")
    |> push_patch(to: socket.assigns.return_to)
  end

  # The identifier is only known to be taken once the insert fails.
  defp creation_failed(socket, _params, {:error, %Ecto.Changeset{data: %Device{}} = changeset}) do
    assign(socket, :form, to_form(changeset, action: :insert))
  end

  defp creation_failed(socket, params, {:error, %Ecto.Changeset{} = changeset}) do
    socket
    |> assign_form(params, :insert)
    |> assign(:certificate_error, certificate_error(changeset))
  end

  defp creation_failed(socket, params, _error) do
    socket
    |> assign_form(params, :insert)
    |> put_flash(:error, "We couldn't add the device. Please contact support if this happens again.")
  end

  # The same certificate shares its key, so it fails on the key before the
  # certificate's own unique index is reached.
  defp certificate_error(%Ecto.Changeset{errors: errors}) do
    cond do
      Keyword.has_key?(errors, :fingerprint) -> "Another device already has this certificate."
      Keyword.has_key?(errors, :public_key_fingerprint) -> "Another device already has this certificate's key."
      true -> "We couldn't save this certificate."
    end
  end

  # The upload is read but kept (`:postpone`) until the device is added, so a
  # form sent back with an error still has its file.
  defp uploaded_certificate(socket) do
    case uploaded_entries(socket, :certificate) do
      {[], []} ->
        :none

      {[_], []} ->
        [contents] =
          consume_uploaded_entries(socket, :certificate, fn %{path: path}, _entry ->
            {:postpone, File.read!(path)}
          end)

        case Certificate.from_pem_or_der(contents) do
          {:ok, otp_cert} -> {:ok, otp_cert}
          {:error, _} -> {:error, "This file isn't a certificate in PEM or DER form."}
        end

      # One that failed (too big, say) is never uploaded, and shows why.
      _not_uploaded ->
        {:error, "Remove this file and choose the certificate again."}
    end
  end

  defp assign_connection(socket, connection) do
    if connection in socket.assigns.connections,
      do: assign(socket, :connection, connection),
      else: socket
  end

  defp assign_form(socket, params, action) do
    changeset = Device.create_changeset(socket.assigns.product, params)

    socket
    |> assign(:form, to_form(changeset, action: action))
    |> assign_matching_groups(Ecto.Changeset.get_field(changeset, :tags) || [])
  end

  # A role limited to tagged devices can't hold `device:create`, so everyone
  # who reaches this can see the product's deployment groups.
  defp assign_matching_groups(%{assigns: %{matched_tags: tags}} = socket, tags), do: socket

  defp assign_matching_groups(%{assigns: %{product: product}} = socket, tags) do
    groups = ManagedDeployments.deployment_groups_matching_tags(product, tags)

    socket
    |> assign(:matching_groups, Enum.map(groups, & &1.name))
    |> assign(:matched_tags, tags)
  end

  defp update_form_tags(%{assigns: %{form: form}} = socket, change) do
    tags = form[:tags].value |> form_tags() |> change.() |> Enum.join(",")
    params = Map.put(form.source.params || %{}, "tags", tags)

    assign_form(socket, params, form.source.action)
  end

  # A tag typed but not yet added when the form is sent is added with it,
  # rather than quietly dropped.
  defp with_unadded_tag(device_params, new_tag) when is_binary(new_tag) and new_tag != "" do
    tags = form_tags(device_params["tags"]) ++ split_tags(new_tag)

    Map.put(device_params, "tags", tags |> Enum.uniq() |> Enum.join(","))
  end

  defp with_unadded_tag(device_params, _new_tag), do: device_params

  defp form_tags(tags) when is_list(tags), do: tags
  defp form_tags(tags) when is_binary(tags), do: split_tags(tags)
  defp form_tags(_tags), do: []

  defp split_tags(text), do: text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id={@id} class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-backdrop p-4 max-sm:items-end max-sm:p-0">
      <.focus_wrap
        id={"#{@id}-dialog"}
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        phx-click-away={is_nil(@added) && JS.patch(@return_to)}
        phx-window-keydown={is_nil(@added) && JS.patch(@return_to)}
        phx-key="escape"
        class="my-auto flex max-h-[calc(100dvh-4rem)] w-140 max-w-full flex-col rounded-md border border-line-default bg-surface-overlay shadow-overlay max-sm:mb-0 max-sm:max-h-[92dvh] max-sm:w-full max-sm:rounded-t-xl max-sm:rounded-b-none max-sm:border-b-0"
      >
        <.form_body
          :if={is_nil(@added)}
          id={@id}
          form={@form}
          available_tags={@available_tags}
          matching_groups={@matching_groups}
          connections={@connections}
          connection={@connection}
          upload={@uploads.certificate}
          certificate_error={@certificate_error}
          return_to={@return_to}
          myself={@myself}
        />
        <.added_body
          :if={@added}
          id={@id}
          added={@added}
          connected?={@connected?}
          device_path={~p"/org/#{@current_scope.org}/#{@product}/devices/#{@added.device}"}
          return_to={@return_to}
          myself={@myself}
        />
      </.focus_wrap>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:form, Form, required: true)
  attr(:available_tags, :list, required: true)
  attr(:matching_groups, :list, required: true)
  attr(:connections, :list, required: true)
  attr(:connection, :string, required: true)
  attr(:upload, :any, required: true)
  attr(:certificate_error, :string, default: nil)
  attr(:return_to, :string, required: true)
  attr(:myself, :any, required: true)

  defp form_body(assigns) do
    ~H"""
    <.dialog_header id={@id} return_to={@return_to}>
      <:title>Add a device</:title>
      Devices add themselves the first time they connect. Add one here to set it up before it does.
    </.dialog_header>

    <.form
      for={@form}
      id={"#{@id}-form"}
      phx-target={@myself}
      phx-change="validate"
      phx-submit="save"
      class="flex min-h-0 flex-1 flex-col"
    >
      <div class="flex min-h-0 flex-1 flex-col gap-5.5 overflow-y-auto px-6 py-5.5 max-sm:px-4">
        <div class="flex flex-col gap-1.5">
          <label for={@form[:identifier].id} class={label_class()}>Identifier</label>
          <input
            type="text"
            id={@form[:identifier].id}
            name={@form[:identifier].name}
            value={@form[:identifier].value}
            autocomplete="off"
            spellcheck="false"
            phx-mounted={JS.focus()}
            phx-debounce="blur"
            class={[text_control_class(@form[:identifier]), "font-mono"]}
          />
          <p class="text-xs text-content-muted">What the device sends when it connects, usually its serial number.</p>
          <.field_errors field={@form[:identifier]} />
        </div>

        <div class="flex flex-col gap-1.5">
          <label for={@form[:description].id} class={label_class()}>Description <span class={optional_class()}>Optional</span></label>
          <input
            type="text"
            id={@form[:description].id}
            name={@form[:description].name}
            value={@form[:description].value}
            phx-debounce="blur"
            class={text_control_class(@form[:description])}
          />
          <.field_errors field={@form[:description]} />
        </div>

        <.tags_field id={@id} form={@form} available_tags={@available_tags} myself={@myself} matching_groups={@matching_groups} />

        <fieldset>
          <legend class={[label_class(), "mb-2"]}>How it connects</legend>
          <%!-- Always rendered, so a file chosen before switching to another
                way stays chosen if the certificate is picked again. --%>
          <.live_file_input upload={@upload} class="hidden" />
          <div class="flex flex-col rounded border border-line-default">
            <.connection_option :for={connection <- @connections} value={connection} checked={connection == @connection} id={@id}>
              <:title>{connection_title(connection)}</:title>
              {connection_help(connection)}
              <:extra :if={connection == "certificate" and @connection == "certificate"}>
                <.certificate_upload upload={@upload} error={@certificate_error} myself={@myself} />
              </:extra>
            </.connection_option>
          </div>
        </fieldset>

        <%!-- The browser opens and closes it; a re-render leaves it as it is. --%>
        <details id={"#{@id}-first-connect"} class="group border-t border-line-subtle pt-4" phx-mounted={JS.ignore_attributes(["open"])}>
          <summary class="flex cursor-pointer list-none items-center gap-2 text-ui/4 font-medium text-content-strong [&::-webkit-details-marker]:hidden">
            <span class="lucide-chevron-right size-3.5 text-content-muted transition-transform group-open:rotate-90" aria-hidden="true"></span>
            Run code when it first connects <span class={optional_class()}>Optional</span>
          </summary>
          <div class="mt-3 flex flex-col gap-1.5">
            <label for={@form[:connecting_code].id} class="sr-only">First connect code</label>
            <textarea
              id={@form[:connecting_code].id}
              name={@form[:connecting_code].name}
              rows="4"
              spellcheck="false"
              phx-debounce="blur"
              class={["min-h-18 w-full bg-surface-raised px-3 py-2.5 font-mono text-xs/5 text-content-body max-sm:text-base/6", control_class(@form[:connecting_code])]}
            ><%= Phoenix.HTML.Form.normalize_value("textarea", @form[:connecting_code].value) %></textarea>
            <p class="text-xs text-content-muted">Elixir the device runs each time it connects. If it fails, you get a notification.</p>
            <.field_errors field={@form[:connecting_code]} />
          </div>
        </details>
      </div>

      <footer class="flex shrink-0 items-center justify-end gap-2 rounded-b-md border-t border-line-default bg-surface-muted px-6 py-3.5 max-sm:rounded-b-none max-sm:px-4 max-sm:pb-[max(--spacing(3.5),env(safe-area-inset-bottom))]">
        <.button type="link" patch={@return_to} class="max-sm:h-11 max-sm:flex-1 max-sm:text-sm">Cancel</.button>
        <.button type="submit" style="primary" phx-disable-with="Adding…" class="max-sm:h-11 max-sm:flex-1 max-sm:text-sm">Add device</.button>
      </footer>
    </.form>
    """
  end

  defp tags_field(assigns) do
    assigns = assign(assigns, :tags, form_tags(assigns.form[:tags].value))

    ~H"""
    <div class="flex flex-col gap-1.5">
      <label for={"#{@id}-new-tag"} class={label_class()}>Tags <span class={optional_class()}>Optional</span></label>
      <input type="hidden" name={@form[:tags].name} value={Enum.join(@tags, ",")} />
      <div class={[
        "flex min-h-8 flex-wrap items-center gap-1.5 bg-surface-raised px-1 py-0.75 focus-within:outline focus-within:-outline-offset-1 focus-within:outline-focus-ring max-sm:min-h-11 max-sm:p-1.5",
        control_class(@form[:tags])
      ]}>
        <span
          :for={tag <- @tags}
          data-tag={tag}
          class="flex h-6 items-center gap-1 rounded border border-line-default bg-surface-muted pr-1 pl-2 font-mono text-xs text-content-body max-sm:h-8 max-sm:pr-0.5"
        >
          {tag}
          <button
            type="button"
            phx-click="remove-tag"
            phx-value-tag={tag}
            phx-target={@myself}
            aria-label={"Remove #{tag}"}
            class="flex cursor-pointer rounded-sm text-content-faint hover:text-content-strong max-sm:p-1.5"
          >
            <span class="lucide-x size-3" aria-hidden="true"></span>
          </button>
        </span>
        <div
          id={"#{@id}-tags-autocomplete"}
          class="relative min-w-24 grow basis-24"
          phx-hook="TagAutocomplete"
          phx-target={@myself}
          data-commit-event="add-tag"
          data-available-tags={Jason.encode!(@available_tags -- @tags)}
        >
          <input
            type="text"
            id={"#{@id}-new-tag"}
            name="new_tag"
            value=""
            placeholder={if(@tags == [], do: "Add a tag")}
            autocomplete="off"
            data-tag-input
            class="h-6 w-full border-0 bg-transparent p-0 pl-1.5 text-ui text-content-strong placeholder:text-content-faint focus:ring-0 max-sm:h-8 max-sm:text-base"
          />
          <ul
            id={"#{@id}-new-tag-suggestions"}
            phx-update="ignore"
            data-tag-suggestions
            role="listbox"
            hidden
            class="absolute z-10 mt-1 max-h-56 w-48 overflow-y-auto rounded-md border border-line-default bg-surface-overlay py-1 shadow-overlay"
          >
          </ul>
        </div>
      </div>
      <p :if={@matching_groups != []} id={"#{@id}-matching-groups"} class="flex items-center gap-1.5 text-xs text-content-muted">
        <span class="lucide-corner-down-right size-3.5 text-content-faint" aria-hidden="true"></span>
        <span>These tags match <.group_names names={@matching_groups} /></span>
      </p>
      <.field_errors field={@form[:tags]} />
    </div>
    """
  end

  attr(:names, :list, required: true)

  defp group_names(assigns) do
    {named, rest} = Enum.split(assigns.names, @named_groups)
    assigns = assign(assigns, named: named, rest: length(rest))

    ~H"""
    <%= for {name, i} <- Enum.with_index(@named) do %>
      {separator(i, length(@named), @rest)}<span class="font-medium text-content-strong">{name}</span>
    <% end %>
    {if @rest > 0, do: " and #{@rest} more"}
    """
  end

  defp separator(0, _count, _rest), do: ""
  defp separator(i, count, 0) when i == count - 1, do: " and "
  defp separator(_i, _count, _rest), do: ", "

  attr(:id, :string, required: true)
  attr(:value, :string, required: true)
  attr(:checked, :boolean, required: true)
  slot(:title, required: true)
  slot(:inner_block, required: true)
  slot(:extra)

  defp connection_option(assigns) do
    ~H"""
    <div class="border-b border-line-default first:rounded-t last:rounded-b last:border-b-0 has-checked:bg-primary/5">
      <label for={"#{@id}-connection-#{@value}"} class="flex cursor-pointer gap-2.5 px-3.5 py-3">
        <span class="flex h-4.5 shrink-0 items-center">
          <input
            type="radio"
            id={"#{@id}-connection-#{@value}"}
            name="connection"
            value={@value}
            checked={@checked}
            class="size-4 border-line-strong bg-surface-raised text-primary checked:border-current checked:bg-current checked:bg-none checked:inset-ring-3 checked:inset-ring-surface-raised focus:ring-0 focus:ring-offset-0 focus-visible:ring-2 focus-visible:ring-focus-ring light:text-indigo-600"
          />
        </span>
        <span class="flex flex-col gap-0.5">
          <span class="text-ui/4.5 font-medium text-content-strong">{render_slot(@title)}</span>
          <span class="text-xs text-content-muted">{render_slot(@inner_block)}</span>
        </span>
      </label>
      <div :if={@extra != []} class="px-3.5 pb-3.5 pl-10">{render_slot(@extra)}</div>
    </div>
    """
  end

  defp connection_title("product"), do: "The product's shared secret"
  defp connection_title("own"), do: "A shared secret of its own"
  defp connection_title("certificate"), do: "Its certificate"

  defp connection_help("product"), do: "Nothing to set up. It's matched by its identifier when it first connects."
  defp connection_help("own"), do: "Made when you add it and shown once, to put on the device."

  defp connection_help("certificate"),
    do: "Upload it as a PEM or DER file, unless one of your CA certificates signed it."

  attr(:upload, :any, required: true)
  attr(:error, :string, default: nil)
  attr(:myself, :any, required: true)

  defp certificate_upload(assigns) do
    ~H"""
    <div class="flex flex-col gap-1.5" phx-drop-target={@upload.ref}>
      <div :for={entry <- @upload.entries} data-certificate-file class="flex h-8 items-center gap-2 rounded border border-line-default bg-surface-raised px-2.5">
        <span class="lucide-file-badge size-3.5 text-content-muted" aria-hidden="true"></span>
        <span class="min-w-0 flex-1 truncate font-mono text-xs text-content-body">{entry.client_name}</span>
        <button
          type="button"
          phx-click="cancel-certificate"
          phx-value-ref={entry.ref}
          phx-target={@myself}
          aria-label={"Remove #{entry.client_name}"}
          class="flex cursor-pointer text-content-faint hover:text-content-strong"
        >
          <span class="lucide-x size-3.5" aria-hidden="true"></span>
        </button>
      </div>
      <.button :if={@upload.entries == []} type="label" size="sm" for={@upload.ref} class="self-start max-sm:h-10 max-sm:text-sm">
        <span class="lucide-upload" aria-hidden="true"></span> Choose a certificate
      </.button>
      <.error :for={error <- upload_errors(@upload)}>{upload_error(error)}</.error>
      <.error :for={entry <- @upload.entries} :if={upload_errors(@upload, entry) != []}>
        {Enum.map_join(upload_errors(@upload, entry), " ", &upload_error/1)}
      </.error>
      <.error :if={@error}>{@error}</.error>
    </div>
    """
  end

  defp upload_error(:too_large), do: "This file is too big for a certificate."
  defp upload_error(:too_many_files), do: "Choose one certificate."
  defp upload_error(_error), do: "This file couldn't be uploaded."

  attr(:id, :string, required: true)
  attr(:added, :map, required: true, doc: "the device added, and the key and secret it was given")
  attr(:connected?, :boolean, required: true)
  attr(:device_path, :string, required: true)
  attr(:return_to, :string, required: true)
  attr(:myself, :any, required: true)

  defp added_body(assigns) do
    ~H"""
    <.dialog_header id={@id} return_to={@return_to}>
      <:title><span class="font-mono font-medium tracking-normal">{@added.device.identifier}</span> added</:title>
      Put its key and secret on the device, then boot it.
    </.dialog_header>

    <div class="flex min-h-0 flex-1 flex-col gap-3.5 overflow-y-auto px-6 pt-5.5 pb-6 max-sm:px-4">
      <div id={"#{@id}-secret"} class="flex flex-col rounded border border-line-default">
        <p class="flex items-center gap-2 rounded-t border-b border-line-default bg-warning-soft px-3.5 py-2.5 text-xs font-medium text-warning-content">
          <span class="lucide-triangle-exclamation-point size-3.5" aria-hidden="true"></span> Copy the secret now. It's only shown once.
        </p>
        <div class="flex min-h-12 items-center gap-4 border-b border-line-subtle px-3.5 py-2 max-sm:flex-wrap max-sm:gap-y-1">
          <span class="w-17 shrink-0 text-label font-medium text-content-faint uppercase">Key</span>
          <code id={"#{@id}-key"} class="min-w-0 flex-1 truncate font-mono text-xs text-content-strong">{@added.key}</code>
          <.copy_button id={"#{@id}-copy-key"} value={@added.key} label="Copy key" />
        </div>
        <div class="flex min-h-12 items-center gap-4 px-3.5 py-2 max-sm:flex-wrap max-sm:gap-y-2">
          <span class="w-17 shrink-0 text-label font-medium text-content-faint uppercase">Secret</span>
          <code class="min-w-0 flex-1 truncate font-mono text-xs text-content-strong">
            <span id={"#{@id}-secret-masked"} class="tracking-widest">{String.duplicate("•", 20)}</span><span id={"#{@id}-secret-shown"} class="hidden">{@added.secret}</span>
          </code>
          <div class="flex shrink-0 gap-2 max-sm:w-full">
            <.button
              id={"#{@id}-show-secret"}
              size="sm"
              class="max-sm:h-10 max-sm:flex-1 max-sm:text-sm"
              phx-click={
                JS.toggle_class("hidden", to: "##{@id}-secret-masked")
                |> JS.toggle_class("hidden", to: "##{@id}-secret-shown")
                |> JS.toggle_class("hidden", to: "##{@id}-show-secret > span")
              }
            >
              <span class="lucide-eye" aria-hidden="true"></span><span>Show</span><span class="lucide-eye-off hidden" aria-hidden="true"></span><span class="hidden">Hide</span>
            </.button>
            <.button
              id={"#{@id}-copy-secret"}
              size="sm"
              style="primary"
              phx-hook="CopyToClipboard"
              data-copy-value={@added.secret}
              class="max-sm:h-10 max-sm:flex-1 max-sm:text-sm"
            >
              <span data-icon="copy" class="lucide-copy" aria-hidden="true"></span><span data-icon="check" class="lucide-check hidden" aria-hidden="true"></span> Copy secret
            </.button>
          </div>
        </div>
      </div>

      <p class="text-xs text-content-muted">
        Give them to <code class="font-mono text-content-body">nerves_hub_link</code>
        as the device's shared secret.
        <a
          href="https://hexdocs.pm/nerves_hub_link/readme.html#shared-secret-authentication"
          target="_blank"
          class="text-content-body underline decoration-line-strong underline-offset-3 hover:text-content-strong"
        >How to configure it</a>
      </p>

      <div id={"#{@id}-waiting"} class="flex gap-3 border-t border-line-subtle pt-4">
        <span :if={!@connected?} class="relative flex size-5 shrink-0 items-center justify-center" aria-hidden="true">
          <span class="absolute size-4 animate-ping rounded-full bg-primary/25 motion-reduce:animate-none"></span>
          <span class="size-2 rounded-full bg-primary"></span>
        </span>
        <span :if={@connected?} class="flex size-5 shrink-0 items-center justify-center" aria-hidden="true">
          <span class="lucide-circle-check--bold size-4 text-success"></span>
        </span>
        <div :if={!@connected?}>
          <p class="text-ui/5 font-medium text-content-strong">Waiting for it to connect…</p>
          <p class="text-ui/5 text-content-muted">This updates on its own when it does. You can close it; the device stays in the list as never connected.</p>
        </div>
        <div :if={@connected?}>
          <p class="text-ui/5 font-medium text-content-strong">Connected</p>
          <p class="text-ui/5 text-content-muted">It's online with its own secret.</p>
        </div>
      </div>
    </div>

    <footer class="flex shrink-0 items-center justify-between gap-2 rounded-b-md border-t border-line-default bg-surface-muted px-6 py-3.5 max-sm:flex-wrap max-sm:rounded-b-none max-sm:px-4 max-sm:pb-[max(--spacing(3.5),env(safe-area-inset-bottom))]">
      <button
        type="button"
        phx-click="add-another"
        phx-target={@myself}
        class="flex cursor-pointer items-center gap-1.5 text-ui/4 font-medium text-primary hover:text-primary-hover max-sm:h-11 light:text-indigo-600 light:hover:text-indigo-500"
      >
        <span class="lucide-plus size-3.5" aria-hidden="true"></span> Add another
      </button>
      <div class="flex gap-2 max-sm:w-full">
        <.button type="link" navigate={@device_path} class="max-sm:h-11 max-sm:flex-1 max-sm:text-sm">Open device</.button>
        <.button id={"#{@id}-done"} type="link" patch={@return_to} class="max-sm:h-11 max-sm:flex-1 max-sm:text-sm">Done</.button>
      </div>
    </footer>
    """
  end

  attr(:id, :string, required: true)
  attr(:value, :string, required: true)
  attr(:label, :string, required: true)

  defp copy_button(assigns) do
    ~H"""
    <.button id={@id} size="sm" square phx-hook="CopyToClipboard" data-copy-value={@value} aria-label={@label} title={@label}>
      <span data-icon="copy" class="lucide-copy" aria-hidden="true"></span>
      <span data-icon="check" class="lucide-check hidden" aria-hidden="true"></span>
    </.button>
    """
  end

  attr(:id, :string, required: true)
  attr(:return_to, :string, required: true)
  slot(:title, required: true)
  slot(:inner_block, required: true)

  defp dialog_header(assigns) do
    ~H"""
    <header class="flex shrink-0 items-start justify-between gap-4 border-b border-line-default px-6 pt-5 pb-4.5 max-sm:px-4">
      <div class="flex min-w-0 flex-col gap-1">
        <h2 id={"#{@id}-title"} class="text-card-title break-all text-content-strong">{render_slot(@title)}</h2>
        <p class="max-w-115 text-ui/4.5 text-content-muted">{render_slot(@inner_block)}</p>
      </div>
      <.link patch={@return_to} aria-label="Close" class="flex size-7 shrink-0 items-center justify-center rounded text-content-muted hover:bg-surface-muted hover:text-content-strong">
        <span class="lucide-x size-4" aria-hidden="true"></span>
      </.link>
    </header>
    """
  end

  defp label_class(), do: "text-ui/4 font-medium text-content-strong"
  defp optional_class(), do: "ml-1 text-xs font-normal text-content-faint"

  defp text_control_class(field) do
    [
      "h-8 w-full bg-surface-raised px-3 text-ui text-content-strong placeholder:text-content-faint max-sm:h-11 max-sm:text-base",
      control_class(field)
    ]
  end

  # The bezel every text control has: a lighter edge, a darker bottom, red
  # when the field has an error.
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

  defp errors_for(field) do
    if Phoenix.Component.used_input?(field),
      do: Enum.map(field.errors, &NervesHubWeb.CoreComponents.translate_error/1),
      else: []
  end
end
