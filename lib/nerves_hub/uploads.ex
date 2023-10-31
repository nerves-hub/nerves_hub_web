defmodule NervesHub.Uploads do
  @callback delete(key :: String.t()) :: :ok | {:error, any()}

  @callback upload(file :: File.io_device(), key :: String.t(), opts :: Keyword.t()) ::
              :ok | {:error, any()}

  @callback url(key :: String.t(), opts :: Keyword.t()) :: String.t()

  def backend() do
    Application.get_env(:nerves_hub, __MODULE__)[:backend]
  end

  def upload(file, key, opts \\ []) do
    backend().upload(file, key, opts)
  end

  def url(key, opts \\ []) do
    backend().url(key, opts)
  end
end

defmodule NervesHub.Uploads.File do
  @behaviour NervesHub.Uploads

  def local_path() do
    Application.get_env(:nerves_hub, __MODULE__)[:local_path]
  end

  @impl NervesHub.Uploads
  def delete(key) do
    path = Path.join(local_path(), key)
    File.rm(path)

    :ok
  end

  @impl NervesHub.Uploads
  def upload(file_path, key, _opts) do
    path = Path.join(local_path(), key)

    dirname = Path.dirname(path)
    File.mkdir_p(dirname)

    case File.copy(file_path, path) do
      {:ok, _} ->
        :ok

      _ ->
        {:error, :uploading}
    end
  end

  @impl NervesHub.Uploads
  def url("/" <> key, opts), do: url(key, opts)

  def url(key, _opts) do
    config = Application.get_env(:nerves_hub, NervesHubWeb.Endpoint)[:url]
    uri = URI.parse("/uploads/#{key}")

    uri = %{
      uri
      | host: config[:host],
        port: config[:port],
        scheme: config[:scheme]
    }

    URI.to_string(uri)
  end
end

defmodule NervesHub.Uploads.S3 do
  @behaviour NervesHub.Uploads

  alias ExAws.S3

  def bucket() do
    Application.get_env(:nerves_hub, __MODULE__)[:bucket]
  end

  @impl NervesHub.Uploads
  def delete(key) do
    bucket()
    |> S3.delete_object(key)
    |> ExAws.request()

    :ok
  end

  @impl NervesHub.Uploads
  def upload(file_path, key, opts) do
    bucket()
    |> S3.put_object(key, File.read!(file_path), Keyword.get(opts, :meta, []))
    |> ExAws.request!()

    :ok
  end

  @impl NervesHub.Uploads
  def url(key, opts) do
    case Keyword.has_key?(opts, :signed) do
      true ->
        config = ExAws.Config.new(:s3)
        {:ok, url} = S3.presigned_url(config, :get, bucket(), key, opts[:signed])
        url

      false ->
        "https://s3.amazonaws.com/#{bucket()}#{key}"
    end
  end
end
