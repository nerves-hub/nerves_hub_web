defmodule BeamwareWeb.FirmwareController do
  use BeamwareWeb, :controller

  alias Ecto.Changeset
  alias Beamware.Firmwares
  alias Beamware.Firmwares.Firmware
  alias Beamware.Accounts.TenantKey

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
         timestamp <- extract_timestamp(metadata),
         product <- extract_product(metadata),
         platform <- extract_platform(metadata),
         architecture <- extract_architecture(metadata),
         {:ok, upload_metadata} <- upload_firmware(path, filename, tenant.id) do
      %{
        tenant_id: tenant.id,
        filename: filename,
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
    firmware = Beamware.Repo.get(Firmware, id)

    if uploader = Application.get_env(:beamware, :firmware_upload) do
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
    if uploader = Application.get_env(:beamware, :firmware_upload) do
      uploader.upload_file(filepath, filename, tenant_id)
    else
      {:error}
    end
  end

  defp extract_product(metadata) do
    Regex.compile!("meta-product=\"([^\"]*)\"")
    |> Regex.run(metadata, capture: :all_but_first)
    |> hd
  end

  defp extract_platform(metadata) do
    Regex.compile!("meta-platform=\"([^\"]*)\"")
    |> Regex.run(metadata, capture: :all_but_first)
    |> hd
  end

  defp extract_architecture(metadata) do
    Regex.compile!("meta-architecture=\"([^\"]*)\"")
    |> Regex.run(metadata, capture: :all_but_first)
    |> hd
  end

  defp extract_timestamp(metadata) do
    Regex.compile!("meta-creation-date=\"([^\"]*)\"")
    |> Regex.run(metadata, capture: :all_but_first)
    |> hd
    |> DateTime.from_iso8601()
    |> case do
      {:ok, datetime, _} -> datetime
    end
  end
end
