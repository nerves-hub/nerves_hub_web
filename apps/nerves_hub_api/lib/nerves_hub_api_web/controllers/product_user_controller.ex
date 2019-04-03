defmodule NervesHubAPIWeb.ProductUserController do
  use NervesHubAPIWeb, :controller

  alias NervesHubWebCore.{Accounts, Products}

  action_fallback(NervesHubAPIWeb.FallbackController)

  plug(:validate_role, product: :admin)

  def index(%{assigns: %{product: product}} = conn, _params) do
    product_users = Products.get_product_users(product)
    render(conn, "index.json", product_users: product_users)
  end

  def add(%{assigns: %{org: org, product: product}} = conn, params) do
    with {:ok, username} <- Map.fetch(params, "username"),
         {:ok, role} <- Map.fetch(params, "role"),
         {:ok, user} <- Accounts.get_user_by_username(username),
         {:ok, product_user} <- Products.add_product_user(product, user, %{role: role}) do
      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        product_user_path(conn, :show, org.name, product.name, user.username)
      )
      |> render("show.json", product_user: product_user)
    end
  end

  def show(%{assigns: %{product: product}} = conn, %{"username" => username}) do
    with {:ok, user} <- Accounts.get_user_by_username(username),
         {:ok, product_user} <- Products.get_product_user(product, user) do
      render(conn, "show.json", product_user: product_user)
    end
  end

  def remove(%{assigns: %{product: product}} = conn, %{"username" => username}) do
    with {:ok, user} <- Accounts.get_user_by_username(username),
         :ok <- Products.remove_product_user(product, user) do
      send_resp(conn, :no_content, "")
    end
  end

  def update(%{assigns: %{product: product}} = conn, %{"username" => username} = params) do
    with {:ok, user} <- Accounts.get_user_by_username(username),
         {:ok, product_user} <- Products.get_product_user(product, user),
         {:ok, role} <- Map.fetch(params, "role"),
         {:ok, product_user} <- Products.change_product_user_role(product_user, role) do
      render(conn, "show.json", product_user: product_user)
    end
  end
end
