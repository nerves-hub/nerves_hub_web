defmodule NervesHubWWWWeb.DeviceController do
  use NervesHubWWWWeb, :controller

  alias NervesHubCore.Devices
  alias NervesHubCore.Devices.Device
  alias Ecto.Changeset

  def index(%{assigns: %{tenant: _tenant, product: product}} = conn, _params) do
    conn
    |> render(
      "index.html",
      devices: Devices.get_devices(product)
    )
  end

  def index(%{assigns: %{tenant: tenant}} = conn, _params) do
    conn
    |> render(
      "index.html",
      devices: Devices.get_devices(tenant)
    )
  end

  def new(%{assigns: %{tenant: _tenant}} = conn, _params) do
    conn
    |> render(
      "new.html",
      changeset: %Changeset{data: %Device{}}
    )
  end

  # def new(%{assigns: %{tenant: _tenant}} = conn, _params) do
  # conn
  # |> redirect(to: dashboard_path(conn, :index))
  # end

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

  def show(%{assigns: %{tenant: tenant}} = conn, %{
        "id" => id
      }) do
    {:ok, device} = Devices.get_device(tenant, id)

    render(conn, "show.html", device: device)
  end

  def edit(%{assigns: %{tenant: tenant}} = conn, %{"id" => id}) do
    {:ok, device} = Devices.get_device(tenant, id)

    conn
    |> render(
      "edit.html",
      device: device,
      changeset: device |> Device.changeset(%{}) |> tags_to_string()
    )
  end

  def update(%{assigns: %{tenant: tenant}} = conn, %{
        "id" => id,
        "device" => params
      }) do
    {:ok, device} = Devices.get_device(tenant, id)

    device
    |> Devices.update_device(params |> tags_to_list())
    |> case do
      {:ok, _device} ->
        conn
        |> put_flash(:info, "Device updated.")
        |> redirect(to: device_path(conn, :show, id))

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
