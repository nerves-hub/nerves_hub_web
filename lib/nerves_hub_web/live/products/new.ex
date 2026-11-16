defmodule NervesHubWeb.Live.Products.New do
  use NervesHubWeb, :live_view

  alias NervesHub.Extensions
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHubWeb.Mounts.OrgCounts

  on_mount(OrgCounts)

  @impl Phoenix.LiveView
  @decorate requires_permission(:"product:create")
  def mount(_params, _session, socket) do
    products = Products.get_products(socket.assigns.current_scope)

    socket
    |> page_title("New Product - #{socket.assigns.current_scope.org.name}")
    |> sidebar_tab(:products)
    |> assign(:form, to_form(Products.change_product(%Product{})))
    |> assign(:products, products)
    |> assign(:available_extensions, extensions())
    |> ok()
  end

  @impl Phoenix.LiveView
  @decorate requires_permission(:"product:create")
  def handle_event("create_product", %{"product" => product_params}, socket) do
    authorized!(:"product:create", socket.assigns.current_scope)

    case Products.create_product(socket.assigns.current_scope.org, product_params) do
      {:ok, product} ->
        socket
        |> put_flash(:info, "Product created successfully.")
        |> push_navigate(to: ~p"/org/#{socket.assigns.current_scope.org}/#{product}/devices")
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  defp extensions() do
    for extension <- Extensions.list(),
        into: %{},
        do: {extension, Extensions.module(extension).description()}
  end
end
