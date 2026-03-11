defmodule NervesHubWeb.Live.Product.Notifications do
  use NervesHubWeb, :live_view

  alias NervesHub.ProductNotifications
  alias NervesHubWeb.Components.Pager
  alias Phoenix.Socket.Broadcast

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    if connected?(socket) do
      ProductNotifications.subscribe(scope.product.id)
    end

    socket
    |> assign(:page_title, "#{scope.product.name} Notifications")
    |> sidebar_tab(:notifications)
    |> fetch_notifications()
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    page_number = String.to_integer(Map.get(params, "page_number", "1"))
    page_size = String.to_integer(Map.get(params, "page_size", "25"))

    socket
    |> fetch_notifications(page_number, page_size)
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_event("dismiss-all", _params, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"product:notifications:dismiss", scope)

    _ = ProductNotifications.delete_all(scope)

    socket
    |> put_flash(:info, "All notifications have been dismissed")
    |> push_patch(to: ~p"/org/#{scope.org}/#{scope.product}/notifications")
    |> noreply()
  end

  def handle_event("set-paginate-opts", %{"page-size" => page_size}, %{assigns: %{current_scope: scope}} = socket) do
    params = %{"page_size" => page_size, "page_number" => "1"}

    socket
    |> push_patch(to: ~p"/org/#{scope.org}/#{scope.product}/notifications?#{params}")
    |> noreply()
  end

  def handle_event("paginate", %{"page" => page_num}, %{assigns: %{current_scope: scope}} = socket) do
    params = %{"page_size" => socket.assigns.result_meta.page_size, "page_number" => page_num}

    socket
    |> push_patch(to: ~p"/org/#{scope.org}/#{scope.product}/notifications?#{params}")
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_info(%Broadcast{event: "created"}, %{assigns: %{result_meta: %{current_page: page}}} = socket)
      when page == 1 do
    socket
    |> put_flash(:info, "New notification is available.")
    |> fetch_notifications()
    |> noreply()
  end

  def handle_info(%Broadcast{event: "created"}, socket) do
    socket
    |> fetch_notifications(socket.assigns.result_meta.current_page, socket.assigns.result_meta.page_size)
    |> put_flash(:info, "New notification is available. Please view the 1st page to see it.")
    |> noreply()
  end

  def handle_info(%Broadcast{event: "dismissed", payload: %{dismissed_by: %{id: user_id, name: name}}}, socket) do
    message =
      if socket.assigns.current_scope.user.id == user_id do
        "All notifications have been dismissed"
      else
        "All notifications have been dismissed by #{name}"
      end

    socket
    |> put_flash(:info, message)
    |> fetch_notifications()
    |> noreply()
  end

  defp fetch_notifications(%{assigns: %{current_scope: scope}} = socket, page_number \\ 1, page_size \\ 25) do
    {notifications, result_meta} = ProductNotifications.paginated_list(scope.product, page_number, page_size)

    socket
    |> assign(:notifications, notifications)
    |> assign(:result_meta, result_meta)
  end
end
