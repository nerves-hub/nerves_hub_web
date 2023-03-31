defmodule NervesHubWeb.Plugs.Product do
  use NervesHubWeb, :plug

  def init(opts) do
    opts
  end

  def call(%{params: %{"product_name" => product_name}} = conn, _opts) do
    %{org: org} = conn.assigns

    product =
      Enum.find(org.products, fn product ->
        product.name == product_name
      end)

    case !is_nil(product) do
      true ->
        assign(conn, :product, product)

      false ->
        conn
        |> put_status(:not_found)
        |> put_view(NervesHubWeb.ErrorView)
        |> render("404.html")
        |> halt()
    end
  end
end
