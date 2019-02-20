defmodule NervesHubWebCore.Firmwares.Upload.S3 do
  alias ExAws.S3

  @spec upload_file(String.t(), String.t()) ::
          :ok
          | {:error, atom()}
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

  @spec metadata(Org.id(), String.t()) :: %{String.t() => binary()}
  def metadata(org_id, filename) do
    %{"s3_key" => Path.join([key_prefix(), Integer.to_string(org_id), filename])}
  end

  @spec download_file(Firmware.t()) ::
          {:ok, String.t()}
          | {:error, String.t()}
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

  @spec delete_file(Firmware.t()) ::
          :ok
          | {:error, any()}
  def delete_file(firmware) do
    s3_key = firmware.upload_metadata["s3_key"]

    S3.delete_object(bucket(), s3_key)
    |> ExAws.request()
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def bucket do
    Application.get_env(:nerves_hub_web_core, __MODULE__)[:bucket]
  end

  def key_prefix() do
    "firmware"
  end
end
