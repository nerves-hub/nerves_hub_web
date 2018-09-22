defmodule NervesHubCore.Firmwares.Upload.S3 do
  alias ExAws.S3

  @spec upload_file(String.t(), String.t()) ::
          :ok
          | {:error, atom()}
  def upload_file(source_path, %{s3_key: s3_key}) do
    bucket = Application.get_env(:nerves_hub_core, __MODULE__)[:bucket]

    source_path
    |> S3.Upload.stream_file()
    |> S3.upload(bucket, s3_key)
    |> ExAws.request()
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @spec metadata(Org.id(), String.t()) :: %{String.t() => binary()}
  def metadata(org_id, filename) do
    %{"s3_key" => Path.join(["firmware", Integer.to_string(org_id), filename])}
  end

  @spec download_file(Firmware.t()) ::
          {:ok, String.t()}
          | {:error, String.t()}
  def download_file(firmware) do
    s3_key = firmware.upload_metadata["s3_key"]
    bucket = Application.get_env(:nerves_hub_core, __MODULE__)[:bucket]

    ExAws.Config.new(:s3)
    |> S3.presigned_url(:get, bucket, s3_key, expires_in: 600)
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
    bucket = Application.get_env(:nerves_hub_core, __MODULE__)[:bucket]

    case S3.delete_object(bucket, s3_key) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end
end
