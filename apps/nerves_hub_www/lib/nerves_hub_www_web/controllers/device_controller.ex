defmodule NervesHubWWWWeb.DeviceController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.Devices
  alias NervesHubWebCore.Devices.Device
  alias Ecto.Changeset

  plug(:validate_role, [product: :delete] when action in [:delete])
  plug(:validate_role, [product: :write] when action in [:new, :create, :edit])
  plug(:validate_role, [product: :read] when action in [:index, :console, :show])

  def index(%{assigns: %{user: user, org: org, product: product}} = conn, _params) do
    conn
    |> live_render(
      NervesHubWWWWeb.DeviceLive.Index,
      # We need to pass csrf_token here so that we can use
      # the delete button from the index.
      # see https://github.com/phoenixframework/phoenix_live_view/issues/111
      session: %{
        auth_user_id: user.id,
        org_id: org.id,
        product_id: product.id,
        csrf_token: get_csrf_token()
      }
    )
  end

  def new(%{assigns: %{org: _org}} = conn, _params) do
    conn
    |> render("new.html", changeset: %Changeset{data: %Device{}})
  end

  def create(%{assigns: %{org: org, product: product}} = conn, %{"device" => params}) do
    params
    |> Map.put("org_id", org.id)
    |> Map.put("product_id", product.id)
    |> Devices.create_device()
    |> case do
      {:ok, _device} ->
        conn
        |> redirect(to: device_path(conn, :index, org.name, product.name))

      {:error, changeset} ->
        conn
        |> render("new.html", changeset: changeset)
    end
  end

  def show(%{assigns: %{user: user, org: org, product: product, device: device}} = conn, _params) do
    conn
    |> live_render(
      NervesHubWWWWeb.DeviceLive.Show,
      session: %{
        auth_user_id: user.id,
        org_id: org.id,
        product_id: product.id,
        device_id: device.id
      }
    )
  end

  def edit(%{assigns: %{user: user, org: org, product: product, device: device}} = conn, _params) do
    conn
    |> live_render(
      NervesHubWWWWeb.DeviceLive.Edit,
      session: %{
        auth_user_id: user.id,
        org_id: org.id,
        product_id: product.id,
        device_id: device.id
      }
    )
  end

  def delete(%{assigns: %{org: org, product: product, device: device}} = conn, _params) do
    {:ok, _device} = Devices.delete_device(device)

    conn
    |> put_flash(:info, "device deleted successfully.")
    |> redirect(to: device_path(conn, :index, org.name, product.name))
  end

  def console(
        %{assigns: %{user: user, org: org, product: product, device: device}} = conn,
        _params
      ) do
    conn
    |> live_render(
      NervesHubWWWWeb.DeviceLive.Console,
      session: %{
        auth_user_id: user.id,
        org_id: org.id,
        product_id: product.id,
        device_id: device.id
      }
    )
  end
end
