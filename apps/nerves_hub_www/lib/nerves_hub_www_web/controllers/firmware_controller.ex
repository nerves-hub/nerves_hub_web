defmodule NervesHubWWWWeb.FirmwareController do
  use NervesHubWWWWeb, :controller

  alias Ecto.Changeset
  alias NervesHubWebCore.Firmwares
  alias NervesHubWebCore.Firmwares.Firmware

  def index(%{assigns: %{product: %{id: product_id}}} = conn, _params) do
    firmwares = Firmwares.get_firmwares_by_product(product_id)

    render(conn, "index.html", firmwares: firmwares)
  end

  def upload(conn, _params) do
    conn
    |> render("upload.html", changeset: %Changeset{data: %Firmware{}})
  end

  def do_upload(%{assigns: %{current_org: org, product: product}} = conn, %{
        "firmware" => %{"file" => %{path: filepath}}
      }) do
    case Firmwares.create_firmware(org, filepath) do
      {:ok, _firmware} ->
        conn
        |> put_flash(:info, "Firmware uploaded")
        |> redirect(to: product_firmware_path(conn, :index, product.id))

      {:error, :no_public_keys} ->
        render_error(
          conn,
          "Please register public keys for verifying firmware signatures first",
          %Changeset{data: %Firmware{}}
        )

      {:error, :invalid_signature} ->
        render_error(
          conn,
          "Firmware corrupt, signature invalid or missing public key",
          %Changeset{data: %Firmware{}}
        )

      {:error,
       %Changeset{
         errors: [product_id: {"can't be blank", [validation: :required]}]
       } = changeset} ->
        render_error(conn, "No matching product could be found.", changeset)

      {:error,
       %Changeset{
         errors: [firmware: {"firmware exceeds maximum size", [size: size, limit: limit]}]
       } = changeset} ->
        render_error(conn, "firmware size #{size} exceeds maximum size #{limit}", changeset)

      {:error, %Changeset{} = changeset} ->
        render_error(conn, "Unknown error uploading firmware.", changeset)

      {:error, error} when is_binary(error) ->
        conn
        |> put_flash(:error, error)
        |> render("upload.html", changeset: %Changeset{data: %Firmware{}})

      _ ->
        render_error(conn, "Uknown error uploading firmware", %Changeset{data: %Firmware{}})
    end
  end

  defp render_error(conn, msg, changeset) do
    conn
    |> put_flash(:error, msg)
    |> render("upload.html", changeset: changeset)
  end

  def download(conn, %{"id" => id}) do
    firmware = NervesHubWebCore.Repo.get(Firmware, id)

    if uploader = Application.get_env(:nerves_hub_web_core, :firmware_upload) do
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
