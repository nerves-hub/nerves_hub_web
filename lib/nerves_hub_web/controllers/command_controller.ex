defmodule NervesHubWeb.CommandController do
  use NervesHubWeb, :controller

  alias NervesHub.Commands
  alias NervesHub.Repo

  plug(:validate_role, [org: :manage] when action in [:new, :create, :delete])
  plug(:validate_role, [org: :view] when action in [:index])

  def index(conn, _params) do
    %{product: product} = conn.assigns

    conn
    |> assign(:commands, Commands.all_by_product(product))
    |> render("index.html")
  end

  def new(conn, _params) do
    changeset =
      %Commands.Command{}
      |> Commands.Command.create_changeset(%{})

    conn
    |> assign(:changeset, changeset)
    |> render("new.html")
  end

  def create(conn, %{"command" => params}) do
    %{org: org, product: product} = conn.assigns

    case Commands.create(product, params) do
      {:ok, _command} ->
        conn
        |> put_flash(:info, "Command created")
        |> redirect(to: Routes.command_path(conn, :index, org.name, product.name))

      {:error, changeset} ->
        conn
        |> assign(:changeset, changeset)
        |> render("new.html")
    end
  end

  def edit(conn, %{"id" => id}) do
    %{org: org, product: product} = conn.assigns

    case Commands.get(product, id) do
      {:ok, command} ->
        changeset = Commands.Command.update_changeset(command, %{})

        conn
        |> assign(:command, command)
        |> assign(:changeset, changeset)
        |> render("edit.html")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: Routes.command_path(conn, :index, org.name, product.name))
    end
  end

  def update(conn, %{"id" => id, "command" => params}) do
    %{org: org, product: product} = conn.assigns

    case Commands.get(product, id) do
      {:ok, command} ->
        case Commands.update(command, params) do
          {:ok, _command} ->
            conn
            |> put_flash(:info, "Command updated")
            |> redirect(to: Routes.command_path(conn, :index, org.name, product.name))

          {:error, changeset} ->
            conn
            |> assign(:command, command)
            |> assign(:changeset, changeset)
            |> render("edit.html")
        end

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: Routes.command_path(conn, :index, org.name, product.name))
    end
  end

  def delete(conn, %{"id" => id}) do
    %{org: org, product: product} = conn.assigns

    case Commands.get(product, id) do
      {:ok, command} ->
        Repo.delete!(command)

        conn
        |> put_flash(:info, "Command deleted")
        |> redirect(to: Routes.command_path(conn, :index, org.name, product.name))

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: Routes.command_path(conn, :index, org.name, product.name))
    end
  end
end
