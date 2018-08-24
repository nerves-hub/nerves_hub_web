defmodule NervesHubWWWWeb.DeviceController do
  use NervesHubWWWWeb, :controller

  alias NervesHubCore.Devices
  alias NervesHubCore.Devices.Device
  alias Ecto.Changeset

  def index(%{assigns: %{current_org: _org, product: product}} = conn, _params) do
    conn
    |> render(
      "index.html",
      devices: Devices.get_devices(product)
    )
  end

  def index(%{assigns: %{current_org: org}} = conn, _params) do
    conn
    |> render(
      "index.html",
      devices: Devices.get_devices(org)
    )
  end

  def new(%{assigns: %{current_org: _org}} = conn, _params) do
    conn
    |> render(
      "new.html",
      changeset: %Changeset{data: %Device{}}
    )
  end

  def create(%{assigns: %{current_org: org}} = conn, %{"device" => params}) do
    params
    |> tags_to_list()
    |> Map.put("org_id", org.id)
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

  def show(%{assigns: %{current_org: org}} = conn, %{
        "id" => id
      }) do
    device = Devices.get_device_by_org!(org, id)
    render(conn, "show.html", device: device)
  end

  def edit(%{assigns: %{current_org: org}} = conn, %{"id" => id}) do
    {:ok, device} = Devices.get_device_by_org(org, id)

    conn
    |> render(
      "edit.html",
      device: device,
      changeset: device |> Device.changeset(%{}) |> tags_to_string()
    )
  end

  def update(%{assigns: %{current_org: org}} = conn, %{
        "id" => id,
        "device" => params
      }) do
    {:ok, device} = Devices.get_device_by_org(org, id)

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

  def delete(%{assigns: %{current_org: org}} = conn, %{
        "id" => id
      }) do
    {:ok, device} = Devices.get_device_by_org(org, id)
    {:ok, _device} = Devices.delete_device(device)

    conn
    |> put_flash(:info, "device deleted successfully.")
    |> redirect(to: device_path(conn, :index))
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
