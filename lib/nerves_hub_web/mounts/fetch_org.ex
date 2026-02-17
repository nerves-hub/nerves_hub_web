defmodule NervesHubWeb.Mounts.FetchOrg do
  import Phoenix.Component

  alias NervesHub.Products

  def on_mount(:default, %{"org_name" => org_name}, _session, socket) do
    %{user: %{orgs: orgs}} = socket.assigns

    org = Enum.find(orgs, &(&1.name == org_name))

    case !is_nil(org) do
      true ->
        picker_banner_urls =
          for product <- org.products,
              url = Products.banner_url(product),
              into: %{},
              do: {product.id, url}

        socket =
          socket
          |> assign(:org, org)
          |> assign(:picker_banner_urls, picker_banner_urls)

        {:cont, socket}

      false ->
        raise NervesHubWeb.NotFoundError
    end
  end
end
