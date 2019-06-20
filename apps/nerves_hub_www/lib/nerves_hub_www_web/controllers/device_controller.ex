defmodule NervesHubWWWWeb.DeviceController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Devices
  alias NervesHubWebCore.Devices.Device
  alias Ecto.Changeset

  plug(:validate_role, [org: :delete] when action in [:delete])
  plug(:validate_role, [org: :write] when action in [:new, :create])
  plug(:validate_role, [org: :read] when action in [:index])

  def index(%{assigns: %{current_org: org, product: product}} = conn, _params) do
    conn
    |> live_render(
      NervesHubWWWWeb.DeviceLive.Index,
      # We need to pass csrf_token here so that we can use
      # the delete button from the index.
      # see https://github.com/phoenixframework/phoenix_live_view/issues/111
      session: %{org_id: org.id, csrf_token: get_csrf_token(), product_id: product.id}
    )
  end

  def new(%{assigns: %{current_org: _org}} = conn, _params) do
    conn
    |> render(
      "new.html",
      changeset: %Changeset{data: %Device{}}
    )
  end

  def create(%{assigns: %{current_org: org, product: product}} = conn, %{"device" => params}) do
    params
    |> Map.put("org_id", org.id)
    |> Map.put("product_id", product.id)
    |> Devices.create_device()
    |> case do
      {:ok, _device} ->
        conn
        |> redirect(to: product_device_path(conn, :index, product))

      {:error, changeset} ->
        conn
        |> render("new.html", changeset: changeset)
    end
  end

  def delete(%{assigns: %{current_org: org, product: product}} = conn, %{
        "id" => id
      }) do
    {:ok, device} = Devices.get_device_by_org(org, id)
    {:ok, _device} = Devices.delete_device(device)

    conn
    |> put_flash(:info, "device deleted successfully.")
    |> redirect(to: product_device_path(conn, :index, product))
  end
end
