defmodule NervesHubWeb.Mounts.FetchProduct do
  import Phoenix.Component

  alias NervesHub.Products

  def on_mount(:default, %{"product_name" => product_name}, _session, socket) do
    %{org: org} = socket.assigns

    product = Enum.find(org.products, &(&1.name == product_name))

    case !is_nil(product) do
      true ->
        {:cont, assign(socket, :product, Products.load_shared_secret_auth(product))}

      false ->
        raise Ecto.NoResultsError
    end
  end
end
