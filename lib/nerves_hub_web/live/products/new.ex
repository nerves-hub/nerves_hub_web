defmodule NervesHubWeb.Live.Products.New do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Extensions
  alias NervesHub.Products
  alias NervesHub.Products.Product

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    products = Products.get_products_by_user_and_org(socket.assigns.user, socket.assigns.org)

    socket =
      socket
      |> page_title("New Product - #{socket.assigns.org.name}")
      |> assign(:form, to_form(Products.change_product(%Product{})))
      |> assign(:products, products)
      |> assign(:available_extensions, extensions())

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("create_product", %{"product" => product_params}, socket) do
    authorized!(:"product:create", socket.assigns.org_user)

    params = Enum.into(product_params, %{"org_id" => socket.assigns.org.id})

    case Products.create_product(params) do
      {:ok, product} ->
        socket
        |> put_flash(:info, "Product created successfully.")
        |> push_navigate(to: ~p"/org/#{socket.assigns.org}/#{product}/devices")
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
