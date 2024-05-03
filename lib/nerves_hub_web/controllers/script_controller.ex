defmodule NervesHubWeb.ScriptController do
  use NervesHubWeb, :controller

  alias NervesHub.Scripts
  alias NervesHub.Repo

  plug(:validate_role, [org: :manage] when action in [:new, :create, :edit, :update, :delete])
  plug(:validate_role, [org: :view] when action in [:index])

  def index(conn, _params) do
    %{product: product} = conn.assigns

    conn
    |> assign(:scripts, Scripts.all_by_product(product))
    |> render("index.html")
  end

  def new(conn, _params) do
    changeset =
      %Scripts.Script{}
      |> Scripts.Script.changeset(%{})

    conn
    |> assign(:changeset, changeset)
    |> render("new.html")
  end

  def create(conn, %{"command" => params}) do
    %{org: org, product: product} = conn.assigns

    case Scripts.create(product, params) do
      {:ok, _command} ->
        conn
        |> put_flash(:info, "Script created")
        |> redirect(to: Routes.script_path(conn, :index, org.name, product.name))

      {:error, changeset} ->
        conn
        |> assign(:changeset, changeset)
        |> render("new.html")
    end
  end

  def edit(conn, %{"id" => id}) do
    %{org: org, product: product} = conn.assigns

    case Scripts.get(product, id) do
      {:ok, command} ->
        changeset = Scripts.Script.changeset(command, %{})

        conn
        |> assign(:command, command)
        |> assign(:changeset, changeset)
        |> render("edit.html")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: Routes.script_path(conn, :index, org.name, product.name))
    end
  end

  def update(conn, %{"id" => id, "command" => params}) do
    %{org: org, product: product} = conn.assigns

    case Scripts.get(product, id) do
      {:ok, command} ->
        case Scripts.update(command, params) do
          {:ok, _command} ->
            conn
            |> put_flash(:info, "Script updated")
            |> redirect(to: Routes.script_path(conn, :index, org.name, product.name))

          {:error, changeset} ->
            conn
            |> assign(:command, command)
            |> assign(:changeset, changeset)
            |> render("edit.html")
        end

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: Routes.script_path(conn, :index, org.name, product.name))
    end
  end

  def delete(conn, %{"id" => id}) do
    %{org: org, product: product} = conn.assigns

    case Scripts.get(product, id) do
      {:ok, command} ->
        Repo.delete!(command)

        conn
        |> put_flash(:info, "Script deleted")
        |> redirect(to: Routes.script_path(conn, :index, org.name, product.name))

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: Routes.script_path(conn, :index, org.name, product.name))
    end
  end
end
