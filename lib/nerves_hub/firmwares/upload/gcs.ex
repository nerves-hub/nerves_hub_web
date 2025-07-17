defmodule NervesHub.Firmwares.Upload.GCS do
  alias GoogleApi.Storage.V1.Api.Objects
  alias GoogleApi.Storage.V1.Connection

  @behaviour NervesHub.Firmwares.Upload

  # Provide URLs to devices that are valid for a day
  @firmware_url_validity_time 60 * 60 * 24

  @type upload_metadata :: %{gcs_key: String.t()}

  @impl NervesHub.Firmwares.Upload
  def upload_file(source_path, %{"gcs_key" => gcs_key}) do
    conn = get_connection()

    try do
      {:ok, _object} = Objects.storage_objects_insert_simple(
        conn,
        bucket(),
        "multipart",
        %{name: gcs_key},
        source_path
      )
      :ok
    rescue
      e -> {:error, e}
    end
  end

  @impl NervesHub.Firmwares.Upload
  def download_file(firmware) do
    gcs_key = firmware.upload_metadata["gcs_key"]

    try do
      {:ok, GcsSignedUrl.generate_v4(
        get_gcs_client(),
        bucket(),
        gcs_key,
        expires: @firmware_url_validity_time
      )}
    rescue
      e -> {:error, e}
    end
  end

  @impl NervesHub.Firmwares.Upload
  def delete_file(%{gcs_key: gcs_key}), do: delete_file(gcs_key)
  def delete_file(%{"gcs_key" => gcs_key}), do: delete_file(gcs_key)

  def delete_file(gcs_key) when is_binary(gcs_key) do
    conn = get_connection()

    try do
      {:ok, _} = Objects.storage_objects_delete(
        conn,
        bucket(),
        gcs_key
      )
      :ok
    rescue
      e -> {:error, e}
    end
  end

  @impl NervesHub.Firmwares.Upload
  def metadata(org_id, filename) do
    %{"gcs_key" => Path.join([key_prefix(), Integer.to_string(org_id), filename])}
  end

  def bucket() do
    Application.get_env(:nerves_hub, __MODULE__)[:bucket]
  end

  def key_prefix() do
    "firmware"
  end

  defp get_gcs_client() do
    cond do
      !is_nil(System.get_env("GOOGLE_APPLICATION_CREDENTIALS")) ->
        GcsSignedUrl.Client.load_from_file(System.fetch_env!("GOOGLE_APPLICATION_CREDENTIALS"))
      !is_nil(System.get_env("GOOGLE_APPLICATION_CREDENTIALS_JSON")) ->
        credentials = System.fetch_env!("GOOGLE_APPLICATION_CREDENTIALS_JSON")
                      |> Jason.decode!()
        GcsSignedUrl.Client.load(credentials)
      true -> nil
    end
  end

  defp get_connection() do
    # https://cloud.google.com/storage/docs/oauth-scopes
    token = Goth.fetch!(NervesHub.Goth)
    Connection.new(token.token)
  end
end
