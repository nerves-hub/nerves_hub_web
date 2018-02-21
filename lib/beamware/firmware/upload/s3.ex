defmodule Beamware.Firmware.Upload.S3 do
  alias ExAws.S3

  def upload_file(filepath, filename, tenant_id) do
    bucket = Application.get_env(:beamware, Beamware.Firmware.Upload.S3)[:bucket]
    random_string = :crypto.strong_rand_bytes(12) |> Base.url_encode64()
    s3_path = Path.join(["firmware", Integer.to_string(tenant_id), random_string, filename])

    filepath
    |> S3.Upload.stream_file()
    |> S3.upload(bucket, s3_path)
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, %{s3_key: s3_path}}
      error -> error
    end
  end

  @spec download_file(Firmware.t()) ::
          {:ok, String.t()}
          | {:error, any()}
  # s3_key
  def download_file(firmware) do
    s3_key = firmware.upload_metadata["s3_key"]
    bucket = Application.get_env(:beamware, Beamware.Firmware.Upload.S3)[:bucket]

    # config = %{
    #   access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    #   secret_access_key: System.get_env("AWS_ACCESS_KEY_ID"),
    #   region: System.get_env("AWS_REGION")
    # }

    # url = Path.join([System.get_env("S3_HOST"), bucket, s3_key])
    # IO.inspect(url)
    # http_method = :get
    # service = :s3
    # # 10 minutes
    # datetime = :calendar.universal_time()
    # expires = 86400
    # ExAws.Auth.presigned_url(http_method, url, service, datetime, config, expires)

    %{
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_ACCESS_KEY_ID"),
      region: System.get_env("AWS_REGION"),
      host: System.get_env("S3_HOST")
    }
    |> S3.presigned_url(:get, bucket, s3_key, expires_in: 600)
    |> case do
      {:ok, url} ->
        {:ok, url}

      error ->
        error
    end
  end
end
