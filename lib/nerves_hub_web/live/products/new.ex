defmodule NervesHubWeb.Live.Products.New do
  use NervesHubWeb, :live_view

  alias NervesHub.Extensions
  alias NervesHub.Products
  alias NervesHub.Products.Product

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    products = Products.get_products(socket.assigns.current_scope)

    socket
    |> page_title("New Product - #{socket.assigns.current_scope.org.name}")
    |> sidebar_tab(:products)
    |> assign(:form, to_form(Products.change_product(%Product{})))
    |> assign(:products, products)
    |> assign(:available_extensions, extensions())
    |> assign(:default_banners, Products.default_banners())
    |> assign_selected_banner(nil)
    |> allow_upload(:banner,
      accept: ~w(.jpg .jpeg .png .webp),
      max_entries: 1,
      max_file_size: 5_000_000
    )
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("select-banner", %{"banner" => ""}, socket) do
    {:noreply,
     socket
     |> cancel_pending_upload()
     |> assign_selected_banner(nil)}
  end

  def handle_event("select-banner", %{"banner" => banner}, socket) do
    {:noreply,
     socket
     |> cancel_pending_upload()
     |> assign_selected_banner(banner)}
  end

  def handle_event("validate-banner", params, socket) do
    socket =
      case params do
        %{"product" => product_params} ->
          changeset =
            %Product{}
            |> Product.changeset(product_params)
            |> Map.put(:action, :validate)

          assign(socket, :form, to_form(changeset))

        _ ->
          socket
      end

    socket =
      if Enum.any?(socket.assigns.uploads.banner.entries) do
        socket
        |> assign(:selected_banner, :custom)
        |> assign(:banner_url, nil)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("create_product", %{"product" => product_params}, socket) do
    authorized!(:"product:create", socket.assigns.current_scope)

    params = Enum.into(product_params, %{"org_id" => socket.assigns.current_scope.org.id})

    with {:ok, product} <- Products.create_product(params),
         {:ok, product} <- maybe_apply_banner(socket, product) do
      socket
      |> put_flash(:info, "Product created successfully.")
      |> push_navigate(to: ~p"/org/#{socket.assigns.current_scope.org}/#{product}/devices")
      |> noreply()
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  defp maybe_apply_banner(socket, product) do
    case socket.assigns.uploads.banner.entries do
      [_entry | _] ->
        [filepath] =
          consume_uploaded_entries(socket, :banner, fn %{path: path}, entry ->
            ext = Path.extname(entry.client_name)
            dest = Path.join(System.tmp_dir(), "banner_#{product.id}#{ext}")
            File.cp!(path, dest)
            {:ok, dest}
          end)

        try do
          Products.update_product_banner(product, filepath)
        after
          File.rm(filepath)
        end

      [] ->
        Products.set_default_banner(product, socket.assigns.selected_banner)
    end
  end

  defp extensions() do
    for extension <- Extensions.list(),
        into: %{},
        do: {extension, Extensions.module(extension).description()}
  end

  defp assign_selected_banner(socket, banner) do
    socket
    |> assign(:selected_banner, banner)
    |> assign(:banner_url, banner && "/images/default_banners/#{banner}")
  end

  defp cancel_pending_upload(socket) do
    Enum.reduce(socket.assigns.uploads.banner.entries, socket, fn entry, socket ->
      cancel_upload(socket, :banner, entry.ref)
    end)
  end
end
