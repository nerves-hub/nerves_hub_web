defmodule BeamwareWeb.DeploymentController do
  use BeamwareWeb, :controller

  alias Beamware.Firmwares
  alias Beamware.Firmwares.Deployment
  alias Ecto.Changeset

  def index(%{assigns: %{tenant: %{id: tenant_id}}} = conn, _params) do
    deployments = Firmwares.get_deployments_by_tenant(tenant_id)
    render(conn, "index.html", deployments: deployments)
  end

  def new(%{assigns: %{tenant: %{id: tenant_id}}} = conn, %{
        "deployment" => %{"firmware_id" => firmware_id}
      }) do
    case Firmwares.get_firmware(firmware_id) do
      {:ok, firmware} ->
        data = %{
          conditions: %{},
          tenant_id: tenant_id,
          firmware_id: firmware.id,
          status: "Paused"
        }

        changeset = Deployment.changeset(%Deployment{}, data)

        conn
        |> render(
          "set-conditions.html",
          changeset: changeset,
          firmware: firmware,
          firmware_options: []
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invalid firmware selected")
        |> redirect(to: "/deployments/new")
    end
  end

  def new(%{assigns: %{tenant: %{id: tenant_id}}} = conn, _) do
    firmwares = Firmwares.get_firmware_by_tenant(tenant_id)

    if length(firmwares) === 0 do
      conn
      |> put_flash(:error, "You must upload a firmware version before creating a deployment")
      |> redirect(to: "/firmware")
    else
      firmware_options =
        firmwares
        |> Enum.map(&[value: &1.id, key: &1.filename])

      conn
      |> render("select-firmware.html", firmware_options: firmware_options)
    end
  end

  def create(%{assigns: %{tenant: %{id: tenant_id}}} = conn, %{
        "deployment" => %{"firmware_id" => firmware_id}
      }) do
    case Firmwares.get_firmware(firmware_id) do
      {:ok, firmware} ->
        data = %{
          conditions: %{},
          tenant_id: tenant_id,
          firmware_id: firmware.id,
          status: "Paused"
        }

        changeset = Deployment.changeset(%Deployment{}, data)

        conn
        |> render("set-conditions.html", changeset: changeset, firmware: firmware)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invalid firmware selected")
        |> redirect(to: "/deployments/new")
    end
  end
end
