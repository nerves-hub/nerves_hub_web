defmodule NervesHubWeb.FirmwareController do
  use NervesHubWeb, :controller

  alias Ecto.Changeset
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Accounts.TenantKey

  def index(%{assigns: %{tenant: tenant, product: %{id: product_id}}} = conn, _params) do
    firmwares = Firmwares.get_firmwares_by_product(product_id)

    render(conn, "index.html", firmwares: firmwares)
  end

  def upload(conn, _params) do
    conn
    |> render("upload.html", changeset: %Changeset{data: %Firmware{}})
  end

  def do_upload(%{assigns: %{tenant: tenant, product: product}} = conn, %{
        "firmware" => %{"file" => %{filename: filename, path: path}}
      }) do
    with {:ok, tenant_key_id} <- verify_signature(path, tenant.tenant_keys),
         {:ok, metadata} <- Firmwares.extract_metadata(path),
         {:ok, architecture} <- Firmware.fetch_metadata_item(metadata, "meta-architecture"),
         {:ok, platform} <- Firmware.fetch_metadata_item(metadata, "meta-platform"),
         {:ok, product_name} <- Firmware.fetch_metadata_item(metadata, "meta-product"),
         {:ok, version} <- Firmware.fetch_metadata_item(metadata, "meta-version"),
         author <- Firmware.get_metadata_item(metadata, "meta-author"),
         description <- Firmware.get_metadata_item(metadata, "meta-description"),
         misc <- Firmware.get_metadata_item(metadata, "meta-misc"),
         uuid <- Firmware.get_metadata_item(metadata, "meta-uuid"),
         vcs_identifier <- Firmware.get_metadata_item(metadata, "meta-vcs-identifier"),
         {:ok, upload_metadata} <- upload_firmware(path, filename, tenant.id) do
      %{
        architecture: architecture,
        author: author,
        description: description,
        misc: misc,
        platform: platform,
        product_name: product_name,
        tenant_id: tenant.id,
        tenant_key_id: tenant_key_id,
        upload_metadata: upload_metadata,
        uuid: uuid,
        vcs_identifier: vcs_identifier,
        version: version
      }
      |> Firmwares.create_firmware()
      |> case do
        {:ok, _firmware} ->
          conn
          |> put_flash(:info, "Firmware uploaded")
          |> redirect(to: product_firmware_path(conn, :index, product.id))

        {:error, changeset} ->
          conn
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
    firmware = NervesHub.Repo.get(Firmware, id)

    if uploader = Application.get_env(:nerves_hub, :firmware_upload) do
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

  defp verify_signature(path, keys) do
    path
    |> Firmwares.verify_signature(keys)
    |> case do
      {:ok, %TenantKey{id: tenant_key_id}} ->
        {:ok, tenant_key_id}

      error ->
        error
    end
  end

  defp upload_firmware(filepath, filename, tenant_id) do
    if uploader = Application.get_env(:nerves_hub, :firmware_upload) do
      uploader.upload_file(filepath, filename, tenant_id)
    else
      {:error}
    end
  end
end
