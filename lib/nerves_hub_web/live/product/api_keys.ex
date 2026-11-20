defmodule NervesHubWeb.Live.Product.ApiKeys do
  @moduledoc """
  Create and deactivate a product's API keys.

  Creating one is a dialog: a name, and a role picked from a list that says
  what each role allows. It is followed by a second dialog holding the key
  itself, which is shown once and only to the person who created it. Nothing
  else on this page can show it again, because only its hash is kept, so that
  dialog can only be closed with its own button.

  Every dialog here, deactivating a key included, is the design system's
  `NervesHubWeb.Components.Dialog.confirm/1`.

  Minting a key takes `product:update`, the same permission as a shared secret.
  A custom role can hold that without the rest of manage, so the picker only
  offers roles that grant nothing beyond the member's own, and
  `NervesHub.Products.ApiKeys.create/3` refuses any other.
  """

  use NervesHubWeb, :live_view

  import NervesHubWeb.Components.ProductSettings, only: [title: 1, tabs: 1]

  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.OrgRoles
  alias NervesHub.Accounts.Scope
  alias NervesHub.Products.ApiKey
  alias NervesHub.Products.ApiKeys
  alias NervesHub.Products.HealthProfiles
  alias NervesHubWeb.Components.Dialog
  alias NervesHubWeb.Components.Utils
  alias NervesHubWeb.CoreComponents
  alias NervesHubWeb.Mounts.RequireEveryDevice

  on_mount(RequireEveryDevice)

  @decorate requires_membership()
  def mount(_params, _session, socket) do
    %{org: org, product: product} = scope = socket.assigns.current_scope

    socket
    |> assign(:page_title, "#{product.name} API Keys")
    |> sidebar_tab(:settings)
    |> assign(:product, product)
    |> assign(:profile_count, HealthProfiles.count_for_product(product))
    |> assign(:role_groups, role_groups(OrgRoles.list_org_roles(org), scope))
    |> assign(:dialog, nil)
    |> reset_form()
    |> assign_api_keys()
    |> ok()
  end

  @decorate requires_permission(:"product:update")
  def handle_event("open-create", _params, socket) do
    socket
    |> assign(:dialog, %{kind: :create, role: default_role(socket.assigns.role_groups), role_menu: false})
    |> reset_form()
    |> noreply()
  end

  @decorate requires_permission(:"product:update")
  def handle_event("toggle-role-menu", _params, socket) do
    socket
    |> update_create_dialog(&%{&1 | role_menu: !&1.role_menu})
    |> noreply()
  end

  @decorate requires_permission(:"product:update")
  def handle_event("close-role-menu", _params, socket) do
    socket
    |> update_create_dialog(&%{&1 | role_menu: false})
    |> noreply()
  end

  @decorate requires_permission(:"product:update")
  def handle_event("pick-role", %{"role" => role}, socket) do
    if role_option(socket.assigns.role_groups, role) do
      socket
      |> update_create_dialog(&%{&1 | role: role, role_menu: false})
      |> noreply()
    else
      noreply(socket)
    end
  end

  # The role lives on the dialog rather than in the form so that it survives a
  # failed create: a changeset holds a custom role as an id, which can't be put
  # back into a control that offers one value for both kinds of role. The form
  # keeps the typed name, which a re-render would otherwise drop.
  @decorate requires_permission(:"product:update")
  def handle_event("validate", %{"api_key" => params}, socket) do
    socket
    |> assign(:form, to_form(params, as: :api_key))
    |> noreply()
  end

  @decorate requires_permission(:"product:update")
  def handle_event("create", %{"api_key" => params}, socket) do
    %{current_scope: scope, product: product} = socket.assigns

    case ApiKeys.create(product, scope.user, role_params(params)) do
      {:ok, api_key, token} ->
        socket
        |> assign(:dialog, %{kind: :reveal, name: api_key.name, token: token, role: ApiKey.assigned_role(api_key)})
        |> reset_form()
        |> assign_api_keys()
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset, as: :api_key))
        |> noreply()
    end
  end

  @decorate requires_permission(:"product:update")
  def handle_event("confirm-deactivate", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.api_keys, &(to_string(&1.id) == id)) do
      nil ->
        noreply(socket)

      api_key ->
        socket
        |> assign(:dialog, %{kind: :deactivate, api_key: api_key})
        |> noreply()
    end
  end

  @decorate requires_permission(:"product:update")
  def handle_event("deactivate", %{"id" => id}, socket) do
    %{current_scope: scope, product: product} = socket.assigns

    case ApiKeys.deactivate(product, scope.user, id) do
      {:ok, api_key} ->
        socket
        |> put_flash(:info, "API key #{api_key.name} has been deactivated.")
        |> assign(:dialog, nil)
        |> assign_api_keys()
        |> noreply()

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "That API key could not be found.")
        |> assign(:dialog, nil)
        |> noreply()
    end
  end

  @decorate requires_membership()
  def handle_event("cancel-dialog", _params, socket) do
    socket
    |> assign(:dialog, nil)
    |> noreply()
  end

  attr(:dialog, :map, required: true)
  attr(:groups, :list, required: true)
  attr(:errors, :list, required: true)

  # The roles on offer, grouped the way the members page groups them, each
  # saying what it allows. A native select can't carry those lines, so this is
  # a button and a listbox rather than a `<select>`; the form carries the
  # picked value in a hidden input.
  #
  # Escape closes the whole dialog rather than just this list: the dialog
  # listens for it on the window, and a popover inside can't take it back.
  #
  # The list hangs past the dialog's footer, which doesn't clip it. On a phone
  # the dialog is a sheet at the bottom of the screen, so it opens upwards
  # over the name field instead, where there is room.
  defp role_field(assigns) do
    assigns =
      assign(assigns, :selected, with(%{role: role} <- role_option(assigns.groups, assigns.dialog.role), do: role))

    ~H"""
    <div class="flex flex-col gap-1.5" phx-click-away={@dialog.role_menu && "close-role-menu"}>
      <span id="api-key-role-label" class="text-ui/4.5 font-medium text-content-body">Role</span>

      <div class="relative">
        <button
          type="button"
          id="api-key-role"
          phx-click="toggle-role-menu"
          aria-haspopup="listbox"
          aria-expanded={to_string(@dialog.role_menu)}
          aria-labelledby="api-key-role-label api-key-role-value"
          class="flex h-8.5 w-full cursor-pointer items-center justify-between gap-2 rounded border border-line-control border-b-line-strong bg-surface-raised px-2.5 text-ui/4.5 text-content-strong focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-focus-ring max-sm:h-11 max-sm:text-base"
        >
          <span id="api-key-role-value" class="truncate">{Utils.role_name(@selected)}</span>
          <span
            class={["lucide-chevron-down size-3.5 text-content-muted transition-transform", @dialog.role_menu && "rotate-180"]}
            aria-hidden="true"
          ></span>
        </button>

        <div
          :if={@dialog.role_menu}
          id="api-key-role-options"
          role="listbox"
          aria-labelledby="api-key-role-label"
          class="absolute inset-x-0 top-full z-10 mt-1 flex max-h-72 flex-col overflow-y-auto rounded-md border border-line-control bg-surface-overlay py-1.5 shadow-overlay max-sm:top-auto max-sm:bottom-full max-sm:mt-0 max-sm:mb-1"
        >
          <div :for={{{group, options}, index} <- Enum.with_index(@groups)} class={["flex flex-col", index > 0 && "mt-1 border-t border-line-default pt-1"]}>
            <p class="px-3 py-1.5 text-label text-content-muted uppercase">{group}</p>
            <button
              :for={option <- options}
              type="button"
              role="option"
              aria-selected={to_string(option.value == @dialog.role)}
              phx-click="pick-role"
              phx-value-role={option.value}
              class={[
                "flex cursor-pointer items-start gap-2 px-3 py-1.75 text-left hover:bg-surface-muted",
                option.value == @dialog.role && "bg-surface-muted"
              ]}
            >
              <span
                class={["mt-0.75 lucide-check--bold size-3.5 text-primary", option.value != @dialog.role && "invisible"]}
                aria-hidden="true"
              ></span>
              <span class="flex flex-col gap-px">
                <span class={["text-ui/4.5 text-content-strong", option.value == @dialog.role && "font-medium"]}>{option.name}</span>
                <span class="text-xs/4 text-content-muted"><.role_description role={option.role} /></span>
              </span>
            </button>
          </div>
        </div>
      </div>

      <p class="text-xs/4 text-content-muted"><.role_description role={@selected} /></p>
      <.error :for={error <- @errors}>{CoreComponents.translate_error(error)}</.error>
      <input type="hidden" name="api_key[role]" value={@dialog.role} />
    </div>
    """
  end

  attr(:role, :any, required: true)

  # What a role allows, under the picker and beside each option. A custom role
  # says what its organization wrote, falling back to the devices it is held to.
  defp role_description(%{role: :view} = assigns) do
    ~H"""
    Read this product's devices, firmware and deployment groups, and run support scripts.
    """
  end

  defp role_description(%{role: :manage} = assigns) do
    ~H"""
    Everything view can do, and change things: upload firmware, send updates, and edit devices and deployment groups.
    """
  end

  defp role_description(%{role: %OrgRole{description: description}} = assigns) when is_binary(description) do
    ~H"""
    {@role.description}
    """
  end

  defp role_description(%{role: %OrgRole{device_tags: [_ | _]}} = assigns) do
    ~H"""
    Devices tagged <span class="font-mono">{Enum.join(@role.device_tags, ", ")}</span> only.
    """
  end

  defp role_description(%{role: %OrgRole{}} = assigns) do
    ~H"""
    A custom role in this organization.
    """
  end

  defp role_description(assigns) do
    ~H"""
    """
  end

  defp update_create_dialog(socket, fun) do
    case socket.assigns.dialog do
      %{kind: :create} = dialog -> assign(socket, :dialog, fun.(dialog))
      _other -> socket
    end
  end

  # The picker carries one value for both kinds of role, the way the members
  # page does: a built-in role's name, or `"custom:<id>"`.
  defp role_params(%{"role" => "custom:" <> org_role_id} = params) do
    Map.merge(params, %{"role" => nil, "org_role_id" => org_role_id})
  end

  defp role_params(params), do: Map.put(params, "org_role_id", nil)

  # The roles this member can give a key, built-in ones first. Only those that
  # grant nothing beyond the member's own role are offered.
  defp role_groups(custom_roles, %Scope{permissions: permissions}) do
    built_in =
      for role <- ApiKey.built_in_roles(), ApiKeys.grantable?(role, permissions) do
        %{value: Atom.to_string(role), name: Utils.role_name(role), role: role}
      end

    custom =
      for role <- custom_roles, ApiKeys.grantable?(role, permissions) do
        %{value: "custom:#{role.id}", name: role.name, role: role}
      end

    [{"Built-in roles", built_in}, {"Custom roles", custom}]
    |> Enum.reject(fn {_group, options} -> options == [] end)
  end

  # The option the picker's value stands for, or nil if it isn't one on offer.
  defp role_option(groups, value) do
    Enum.find_value(groups, fn {_group, options} -> Enum.find(options, &(&1.value == value)) end)
  end

  # View when it is on offer: the narrowest built-in role, so anything wider is
  # always a deliberate pick. A member whose own role lacks part of view starts
  # on the first role they can give.
  defp default_role(groups) do
    case {role_option(groups, "view"), groups} do
      {%{value: value}, _groups} -> value
      {nil, [{_group, [%{value: value} | _]} | _]} -> value
      {nil, []} -> nil
    end
  end

  defp reset_form(socket), do: assign(socket, :form, to_form(%{"name" => ""}, as: :api_key))

  defp assign_api_keys(socket) do
    api_keys = ApiKeys.list(socket.assigns.product)

    socket
    |> assign(:api_keys, api_keys)
    |> assign(:api_key_count, Enum.count(api_keys, &is_nil(&1.deactivated_at)))
  end
end
