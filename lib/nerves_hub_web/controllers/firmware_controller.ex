defmodule NervesHubWeb.FirmwareController do
  use NervesHubWeb, :controller

  alias Ecto.Changeset
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Accounts.TenantKey

  def index(%{assigns: %{tenant: %{id: tenant_id}}} = conn, _params) do
    firmwares = Firmwares.get_firmware_by_tenant(tenant_id)

    render(conn, "index.html", firmwares: firmwares)
  end

  def upload(conn, _params) do
    conn
    |> render("upload.html", changeset: %Changeset{data: %Firmware{}})
  end

  def do_upload(%{assigns: %{tenant: tenant}} = conn, %{
        "firmware" => %{"file" => %{filename: filename, path: path}}
      }) do
    with {:ok, signed} <- Firmwares.verify_firmware(path),
         {:ok, tenant_key_id} <- verify_signature(path, signed, tenant.tenant_keys),
         {:ok, metadata} <- Firmwares.extract_metadata(path),
         {:ok, version} <- Firmware.metadata_item(metadata, "meta-version"),
         {:ok, product} <- Firmware.metadata_item(metadata, "meta-product"),
         {:ok, platform} <- Firmware.metadata_item(metadata, "meta-platform"),
         {:ok, architecture} <- Firmware.metadata_item(metadata, "meta-architecture"),
         {:ok, timestamp} <- Firmware.timestamp(metadata),
         {:ok, upload_metadata} <- upload_firmware(path, filename, tenant.id) do
      %{
        tenant_id: tenant.id,
        version: version,
        product: product,
        platform: platform,
        architecture: architecture,
        timestamp: timestamp,
        signed: if(signed == :signed, do: true, else: false),
        tenant_key_id: tenant_key_id,
        metadata: metadata,
        upload_metadata: upload_metadata
      }
      |> Firmwares.create_firmware()
      |> case do
        {:ok, _firmware} ->
          conn
          |> put_flash(:info, "Firmware uploaded")
          |> redirect(to: "/firmware")

        {:error, changeset} ->
          conn
          |> render("upload.html", changeset: changeset)
      end
    else
      {:error, :corrupt_firmware, message} ->
        conn
        |> put_flash(:error, "Firmware is invalid or corrupt: #{message}")
        |> render("upload.html", changeset: %Changeset{data: %Firmware{}})

      {:error, :invalid_signature} ->
        conn
        |> put_flash(:error, "Firmware signature invalid or missing public key")
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

  defp verify_signature(_path, signed, _keys) when signed === :unsigned do
    {:ok, nil}
  end

  defp verify_signature(path, signed, keys) when signed === :signed do
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
