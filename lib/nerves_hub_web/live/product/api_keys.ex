defmodule NervesHubWeb.Live.Product.ApiKeys do
  @moduledoc """
  Create and deactivate a product's API keys.

  A new key is shown once, straight after it is created, and only to the person
  who created it. Nothing else on this page can show it again, because only its
  hash is kept.

  Minting a key takes `product:update`, the same permission as a shared secret:
  a key is never more powerful than the member who created it, since the roles
  on offer stop at manage and a custom role cannot hold the permissions that
  run the organization.
  """

  use NervesHubWeb, :live_view

  import NervesHubWeb.Components.ProductSettings, only: [title: 1, tabs: 1]

  alias NervesHub.Accounts.OrgRoles
  alias NervesHub.Products.ApiKey
  alias NervesHub.Products.ApiKeys
  alias NervesHub.Products.HealthProfiles
  alias NervesHubWeb.Components.Utils
  alias NervesHubWeb.Mounts.RequireEveryDevice

  on_mount(RequireEveryDevice)

  @decorate requires_membership()
  def mount(_params, _session, socket) do
    %{org: org, product: product} = socket.assigns.current_scope

    socket
    |> assign(:page_title, "#{product.name} API Keys")
    |> sidebar_tab(:settings)
    |> assign(:product, product)
    |> assign(:profile_count, HealthProfiles.count_for_product(product))
    |> assign(:custom_roles, OrgRoles.list_org_roles(org))
    |> assign(:new_key, nil)
    |> assign_form()
    |> assign_api_keys()
    |> ok()
  end

  @decorate requires_permission(:"product:update")
  def handle_event("create", %{"api_key" => params}, socket) do
    %{current_scope: scope, product: product} = socket.assigns

    case ApiKeys.create(product, scope.user, role_params(params)) do
      {:ok, api_key, token} ->
        socket
        |> assign(:new_key, %{name: api_key.name, token: token})
        |> assign_form()
        |> assign_api_keys()
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset, as: :api_key))
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
        |> assign(:new_key, nil)
        |> assign_api_keys()
        |> noreply()

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "That API key could not be found.")
        |> noreply()
    end
  end

  @decorate requires_membership()
  def handle_event("dismiss-new-key", _params, socket) do
    socket
    |> assign(:new_key, nil)
    |> noreply()
  end

  # The select carries one value for both kinds of role, the way the members
  # page does: a built-in role's name, or `"custom:<id>"`.
  defp role_params(%{"role" => "custom:" <> org_role_id} = params) do
    Map.merge(params, %{"role" => nil, "org_role_id" => org_role_id})
  end

  defp role_params(params), do: Map.put(params, "org_role_id", nil)

  # View by default: the narrower of the two, so the wider one is always a
  # deliberate pick.
  defp assign_form(socket) do
    assign(socket, :form, to_form(Ecto.Changeset.change(%ApiKey{role: :view}), as: :api_key))
  end

  defp assign_api_keys(socket) do
    assign(socket, :api_keys, ApiKeys.list(socket.assigns.product))
  end

  defp role_options(custom_roles), do: Utils.role_options(custom_roles, ApiKey.built_in_roles())

  defp role_name(api_key), do: Utils.role_name(api_key)
end
