defmodule NervesHubWebCore.Firmwares.Upload.S3 do
  alias ExAws.S3

  @behaviour NervesHubWebCore.Firmwares.Upload

  @type upload_metadata :: %{s3_key: String.t()}

  @impl NervesHubWebCore.Firmwares.Upload
  def upload_file(source_path, %{"s3_key" => s3_key}) do
    source_path
    |> S3.Upload.stream_file()
    |> S3.upload(bucket(), s3_key)
    |> ExAws.request()
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @impl NervesHubWebCore.Firmwares.Upload
  def download_file(firmware) do
    s3_key = firmware.upload_metadata["s3_key"]

    ExAws.Config.new(:s3)
    |> S3.presigned_url(:get, bucket(), s3_key, expires_in: 600)
    |> case do
      {:ok, url} ->
        {:ok, url}

      error ->
        error
    end
  end

  @impl NervesHubWebCore.Firmwares.Upload
  def delete_file(firmware) do
    s3_key = firmware.upload_metadata["s3_key"]

    S3.delete_object(bucket(), s3_key)
    |> ExAws.request()
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @impl NervesHubWebCore.Firmwares.Upload
  def metadata(org_id, filename) do
    %{"s3_key" => Path.join([key_prefix(), Integer.to_string(org_id), filename])}
  end

  def bucket do
    Application.get_env(:nerves_hub_web_core, __MODULE__)[:bucket]
  end

  def key_prefix() do
    "firmware"
  end
end
