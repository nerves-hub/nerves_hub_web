defmodule NervesHubWeb.Mounts.AssignBannerUrl do
  import Phoenix.Component

  alias NervesHub.Products

  def on_mount(:default, _params, _session, socket) do
    banner_url =
      case socket.assigns.current_scope do
        %{product: %{} = product} -> Products.banner_url(product)
        _ -> nil
      end

    {:cont, assign(socket, :banner_url, banner_url)}
  end
end
