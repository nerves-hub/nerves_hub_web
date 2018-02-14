defmodule BeamwareWeb.DeviceController do
  use BeamwareWeb, :controller

  alias Beamware.Devices
  alias Beamware.Devices.Device
  alias Ecto.Changeset

  def index(conn, _params) do
    conn
    |> render(
      "index.html",
      devices: Devices.get_devices(conn.assigns.tenant)
    )
  end

  def new(conn, _params) do
    conn
    |> render(
      "new.html",
      changeset: %Changeset{data: %Device{}}
    )
  end

  def create(conn, %{"device" => params}) do
    tags =
      params["tags"]
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    device_params = %{params | "tags" => tags}

    conn.assigns.tenant
    |> Devices.create_device(device_params)
    |> case do
      {:ok, _device} ->
        conn
        |> redirect(to: device_path(conn, :index))

      {:error, changeset} ->
        collapsed_tags =
          changeset
          |> Changeset.get_field(:tags, "")
          |> Enum.join(",")

        changeset =
          changeset
          |> Changeset.put_change(:tags, collapsed_tags)

        conn
        |> render("new.html", changeset: changeset)
    end
  end
end
