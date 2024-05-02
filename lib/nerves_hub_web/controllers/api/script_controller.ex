defmodule NervesHubWeb.API.ScriptController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Scripts
  alias NervesHub.Devices

  def index(conn, %{"identifier" => identifier}) do
    %{user: user} = conn.assigns

    case Devices.get_by_identifier(identifier) do
      {:ok, device} ->
        if Accounts.has_org_role?(device.org, user, :view) do
          conn
          |> assign(:scripts, Scripts.all_by_product(device.product))
          |> render("index.json")
        else
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(403, Jason.encode!(%{status: "missing required role: read"}))
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(NervesHubWeb.API.ErrorView)
        |> render(:"404")
    end
  end

  def send(conn, %{"identifier" => identifier, "id" => id}) do
    %{user: user} = conn.assigns

    case Devices.get_by_identifier(identifier) do
      {:ok, device} ->
        if Accounts.has_org_role?(device.org, user, :view) do
          case Scripts.get(device.product, id) do
            {:ok, command} ->
              text(conn, Scripts.Runner.send(device, command))

            {:error, :not_found} ->
              conn
              |> put_status(404)
              |> put_view(NervesHubWeb.API.ErrorView)
              |> render(:"404")
          end
        else
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(403, Jason.encode!(%{status: "missing required role: read"}))
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(NervesHubWeb.API.ErrorView)
        |> render(:"404")
    end
  end
end
