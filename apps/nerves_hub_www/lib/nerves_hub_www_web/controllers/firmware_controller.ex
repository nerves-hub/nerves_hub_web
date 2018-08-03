defmodule NervesHubWWWWeb.FirmwareController do
  use NervesHubWWWWeb, :controller

  alias Ecto.Changeset
  alias NervesHubCore.Firmwares
  alias NervesHubCore.Firmwares.Firmware
  alias NervesHubCore.Accounts.TenantKey

  def index(%{assigns: %{product: %{id: product_id}}} = conn, _params) do
    firmwares = Firmwares.get_firmwares_by_product(product_id)

    render(conn, "index.html", firmwares: firmwares)
  end

  def upload(conn, _params) do
    conn
    |> render("upload.html", changeset: %Changeset{data: %Firmware{}})
  end

  def do_upload(%{assigns: %{tenant: tenant, product: product}} = conn, %{
        "firmware" => %{"file" => %{path: filepath}}
      }) do
    with {:ok, firmware_params} <- Firmwares.prepare_firmware_params(tenant, filepath) do
      case Firmwares.create_firmware(firmware_params) do
        {:ok, _firmware} ->
          conn
          |> put_flash(:info, "Firmware uploaded")
          |> redirect(to: product_firmware_path(conn, :index, product.id))

        {:error,
         %Ecto.Changeset{
           errors: [product_id: {"can't be blank", [validation: :required]}]
         } = changeset} ->
          conn
          |> put_flash(:error, "No matching product could be found.")
          |> render("upload.html", changeset: changeset)

        {:error, changeset} ->
          conn
          |> put_flash(:error, "Unknown error uploading firmware.")
          |> render("upload.html", changeset: changeset)
      end
    else
      {:error, :no_public_keys} ->
        conn
        |> put_flash(
          :error,
          "Please register public keys for verifying firmware signatures first"
        )
        |> render("upload.html", changeset: %Changeset{data: %Firmware{}})

      {:error, :invalid_signature} ->
        conn
        |> put_flash(:error, "Firmware corrupt, signature invalid or missing public key")
        |> render("upload.html", changeset: %Changeset{data: %Firmware{}})

      _ ->
        conn
        |> put_flash(:error, "Unknown error uploading firmware")
        |> render("upload.html", changeset: %Changeset{data: %Firmware{}})
    end
  end

  def download(conn, %{"id" => id}) do
    firmware = NervesHubCore.Repo.get(Firmware, id)

    if uploader = Application.get_env(:nerves_hub_www, :firmware_upload) do
      uploader.download_file(firmware)
      |> case do
        {:ok, url} ->
          conn
          |> redirect(external: url)

        error ->
          error
      end
    else
      {:error}
    end
  end

end
