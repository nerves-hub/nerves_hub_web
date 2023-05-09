defmodule NervesHubWeb.Plugs.FetchUser do
  import Ecto.Query
  import Plug.Conn

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Org
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, "auth_user_id") do
      nil ->
        conn

      user_id ->
        case Accounts.get_user(user_id) do
          {:ok, user} ->
            # Preload orgs and products for the navigation bar
            # Since we've loaded everything then we can reuse it for plugs
            # further down the pipeline
            org_query = from(o in Org, where: is_nil(o.deleted_at))
            product_query = from(p in Product, where: is_nil(p.deleted_at))
            user = Repo.preload(user, orgs: {org_query, products: product_query})

            conn
            |> assign(:user, user)
            |> assign(:orgs, user.orgs)
            |> assign(:user_token, Phoenix.Token.sign(conn, "user salt", user.id))

          _ ->
            conn
        end
    end
  end
end
