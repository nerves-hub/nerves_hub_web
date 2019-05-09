defmodule NervesHubWWWWeb.DeviceController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Devices
  alias NervesHubWebCore.Devices.Device
  alias Ecto.Changeset

  plug(:validate_role, [org: :delete] when action in [:delete])
  plug(:validate_role, [org: :write] when action in [:new, :create])

  def new(%{assigns: %{current_org: _org}} = conn, _params) do
    conn
    |> render(
      "new.html",
      changeset: %Changeset{data: %Device{}}
    )
  end

  def create(%{assigns: %{current_org: org}} = conn, %{"device" => params}) do
    params
    |> Map.put("org_id", org.id)
    |> Devices.create_device()
    |> case do
      {:ok, _device} ->
        conn
        |> redirect(to: device_path(conn, NervesHubWWWWeb.DeviceLive.Index))

      {:error, changeset} ->
        conn
        |> render("new.html", changeset: changeset)
    end
  end

  def delete(%{assigns: %{current_org: org}} = conn, %{
        "id" => id
      }) do
    {:ok, device} = Devices.get_device_by_org(org, id)
    {:ok, _device} = Devices.delete_device(device)

    conn
    |> put_flash(:info, "device deleted successfully.")
    |> redirect(to: device_path(conn, NervesHubWWWWeb.DeviceLive.Index))
  end
end
