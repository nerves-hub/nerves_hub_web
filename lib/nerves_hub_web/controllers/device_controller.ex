defmodule NervesHubWeb.DeviceController do
  use NervesHubWeb, :controller

  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias Ecto.Changeset

  plug(NervesHubWeb.Plugs.FetchDevice when action in [:edit, :update])

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

  def create(%{assigns: %{tenant: tenant}} = conn, %{"device" => params}) do
    params
    |> tags_to_list()
    |> Map.put("tenant_id", tenant.id)
    |> Devices.create_device()
    |> case do
      {:ok, _device} ->
        conn
        |> redirect(to: device_path(conn, :index))

      {:error, changeset} ->
        conn
        |> render("new.html", changeset: changeset |> tags_to_string())
    end
  end

  def edit(conn, _params) do
    conn
    |> render(
      "edit.html",
      changeset: conn.assigns.device |> Device.changeset(%{}) |> tags_to_string()
    )
  end

  def update(conn, %{"device" => params}) do
    conn.assigns.device
    |> Devices.update_device(params |> tags_to_list())
    |> case do
      {:ok, _device} ->
        conn
        |> put_flash(:info, "Device updated.")
        |> redirect(to: device_path(conn, :edit, conn.assigns.device.id))

      {:error, changeset} ->
        conn
        |> render("edit.html", changeset: changeset)
    end
  end

  @doc """
  Convert tags from a list to a comma-separated list (in a string)
  """
  def tags_to_string(%Changeset{} = changeset) do
    tags =
      changeset
      |> Changeset.get_field(:tags)

    tags =
      (tags || [])
      |> Enum.join(",")

    changeset
    |> Changeset.put_change(:tags, tags)
  end

  def tags_to_list(%{"tags" => ""} = params) do
    %{params | "tags" => []}
  end

  def tags_to_list(params) do
    tags =
      params["tags"]
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    %{params | "tags" => tags}
  end
end
