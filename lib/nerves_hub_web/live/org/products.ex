defmodule NervesHubWeb.Live.Org.Products do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Products
  alias NervesHub.Products.Product

  embed_templates("product_templates/*")

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    socket
    |> apply_action(socket.assigns.live_action, params)
    |> noreply()
  end

  defp apply_action(socket, :index, _params) do
    products = Products.get_products_by_user_and_org(socket.assigns.user, socket.assigns.org)

    socket
    |> page_title("Products - #{socket.assigns.org.name}")
    |> assign(:products, products)
    |> render_with(&products_template/1)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> page_title("New Product - #{socket.assigns.org.name}")
    |> assign(:form, to_form(Products.change_product(%Product{})))
    |> render_with(&new_product_template/1)
  end

  @impl Phoenix.LiveView
  def handle_event("create_product", %{"product" => product_params}, socket) do
    authorized!(:create_product, socket.assigns.org_user)

    params = Enum.into(product_params, %{"org_id" => socket.assigns.org.id})

    case Products.create_product(params) do
      {:ok, product} ->
        socket
        |> put_flash(:info, "Product created successfully.")
        |> push_navigate(to: "/org/#{socket.assigns.org.name}/#{product.name}/devices")
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end
end
