defmodule NervesHubWWWWeb.DeviceController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Devices
  alias NervesHubWebCore.Devices.Device
  alias Ecto.Changeset

  plug(:validate_role, [org: :delete] when action in [:delete])
  plug(:validate_role, [org: :write] when action in [:new, :create, :edit, :update])
  plug(:validate_role, [org: :read] when action in [:index, :show])

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

  def console(%{assigns: %{current_org: org, user: user}} = conn, %{
        "id" => id
      }) do
    device = Devices.get_device_by_org!(org, id)
    org_user = Enum.find(user.org_users, %{role: :read_only}, &(&1.org_id == org.id))

    live_render(conn, NervesHubWWWWeb.DeviceLive.Console,
      session: %{device: device, username: user.username, user_role: org_user.role}
    )
  end

  def create(%{assigns: %{current_org: org}} = conn, %{"device" => params}) do
    params
    |> Map.put("org_id", org.id)
    |> Devices.create_device()
    |> case do
      {:ok, _device} ->
        conn
        |> redirect(to: device_path(conn, :index))

      {:error, changeset} ->
        conn
        |> render("new.html", changeset: changeset)
    end
  end

  def show(%{assigns: %{current_org: org, user: user}} = conn, %{
        "id" => id
      }) do
    device = Devices.get_device_by_org!(org, id)
    live_render(conn, NervesHubWWWWeb.DeviceLive.Show, session: %{device: device, user: user})
  end

  def edit(%{assigns: %{current_org: org}} = conn, %{"id" => id}) do
    {:ok, device} = Devices.get_device_by_org(org, id)

    live_render(
      conn,
      NervesHubWWWWeb.DeviceLive.Edit,
      session: %{
        device: device,
        changeset: Device.changeset(device, %{})
      }
    )
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
end
