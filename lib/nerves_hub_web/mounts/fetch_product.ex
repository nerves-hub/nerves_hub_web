defmodule NervesHubWeb.Mounts.FetchProduct do
  import Phoenix.Component

  def on_mount(:default, %{"product_name" => product_name}, _session, socket) do
    %{org: org} = socket.assigns

    socket =
      assign_new(socket, :product, fn ->
        Enum.find(org.products, &(&1.name == product_name))
      end)

    unless socket.assigns.product do
      raise NervesHubWeb.NotFoundError
    end

    {:cont, socket}
  end
end
