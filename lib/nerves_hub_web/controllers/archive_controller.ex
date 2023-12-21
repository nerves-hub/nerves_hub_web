defmodule NervesHubWeb.ArchiveController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Archives

  plug(:validate_role, [org: :manage] when action in [:new, :create, :delete])
  plug(:validate_role, [org: :view] when action in [:index, :show])

  def index(conn, _params) do
    %{product: product} = conn.assigns

    conn
    |> assign(:archives, Archives.all_by_product(product))
    |> render("index.html")
  end

  def show(conn, %{"uuid" => uuid}) do
    %{user: user} = conn.assigns

    case Archives.get(uuid) do
      {:ok, archive} ->
        if Accounts.has_org_role?(archive.product.org, user, :view) do
          conn
          |> assign(:archive, archive)
          |> render("show.html")
        else
          conn
          |> put_status(404)
          |> put_view(NervesHubWeb.ErrorView)
          |> render(:"401")
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(NervesHubWeb.ErrorView)
        |> render(:"404")
    end
  end

  def download(conn, %{"uuid" => uuid}) do
    %{user: user} = conn.assigns

    case Archives.get(uuid) do
      {:ok, archive} ->
        if Accounts.has_org_role?(archive.product.org, user, :view) do
          redirect(conn, external: Archives.url(archive))
        else
          conn
          |> put_status(404)
          |> put_view(NervesHubWeb.ErrorView)
          |> render(:"404")
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(NervesHubWeb.ErrorView)
        |> render(:"404")
    end
  end

  def new(conn, _params) do
    render(conn, "new.html")
  end

  def create(conn, %{"archive" => %{"file" => file}}) do
    %{org: org, product: product} = conn.assigns

    case Archives.create(product, file.path) do
      {:ok, _archive} ->
        conn
        |> put_flash(:info, "Archive Uploaded")
        |> redirect(to: Routes.archive_path(conn, :index, org.name, product.name))
    end
  end

  def delete(conn, %{"uuid" => _uuid}) do
    %{org: org, product: product} = conn.assigns

    conn
    |> put_flash(:info, "Archive Deleted")
    |> redirect(to: Routes.archive_path(conn, :index, org.name, product.name))
  end
end
