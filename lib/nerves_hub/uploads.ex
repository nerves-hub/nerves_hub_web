defmodule NervesHub.Uploads do
  @callback delete(key :: String.t()) :: :ok | {:error, any()}

  @callback upload(file_path :: String.t(), key :: String.t(), opts :: Keyword.t()) ::
              :ok | {:error, any()}

  @callback url(key :: String.t(), opts :: Keyword.t()) :: String.t()

  def backend() do
    Application.get_env(:nerves_hub, __MODULE__)[:backend]
  end

  def delete(key) do
    backend().delete(key)
  end

  def upload(file, key, opts \\ []) do
    backend().upload(file, key, opts)
  end

  def url(key, opts \\ []) do
    backend().url(key, opts)
  end
end

defmodule NervesHub.Uploads.DownloadHost do
  @moduledoc """
  Serves presigned download URLs from a hostname other than the bucket's.

  A CDN or proxy in front of the bucket gives downloads a hostname you control
  and a certificate you manage, but it cannot re-sign the request. It forwards
  the presigned query string and addresses the bucket itself, so the signature
  has to match what the *bucket* receives rather than what the client dialled.

  So a URL is signed for the bucket's virtual-hosted endpoint, which is the form
  those proxies send upstream, and only then has its host replaced. Signing for
  the public hostname instead fails with `SignatureDoesNotMatch`.

  With `S3_DOWNLOAD_HOST` unset, nothing here changes a URL.
  """

  @doc """
  The configured public hostname, or `nil` when downloads come straight from the
  bucket.
  """
  @spec host() :: String.t() | nil
  def host(), do: Application.get_env(:nerves_hub, :s3_download_host)

  @doc """
  Presign options that put the bucket in the host rather than the path.

  Left alone when no download host is configured, so a deployment without one
  keeps whichever addressing style it already uses.
  """
  @spec presign_opts(keyword()) :: keyword()
  def presign_opts(opts) do
    case host() do
      nil -> opts
      _host -> Keyword.put(opts, :virtual_host, true)
    end
  end

  @doc """
  Swaps the bucket's hostname for the public one, leaving the path and the query
  (and therefore the signature) untouched.
  """
  @spec rewrite(String.t()) :: String.t()
  def rewrite(url) do
    case host() do
      nil ->
        url

      host ->
        url
        |> URI.parse()
        |> Map.merge(%{scheme: "https", host: host, port: 443, authority: nil, userinfo: nil})
        |> URI.to_string()
    end
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
    :ok = File.rm(path)

    :ok
  end

  @impl NervesHub.Uploads
  def upload(file_path, key, _opts) do
    path = Path.join(local_path(), key)

    dirname = Path.dirname(path)
    _ = File.mkdir_p(dirname)

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
  alias NervesHub.Uploads.DownloadHost

  @upload_timeout to_timeout(minute: 1)

  def bucket() do
    Application.get_env(:nerves_hub, __MODULE__)[:bucket]
  end

  @impl NervesHub.Uploads
  def delete(key) do
    {:ok, _} =
      bucket()
      |> S3.delete_object(key)
      |> ExAws.request()

    :ok
  end

  @impl NervesHub.Uploads
  def upload(file_path, key, opts) do
    # Stream the file up in parts rather than reading it whole. Archives and
    # firmware images run to tens of megabytes, and `File.read!/1` put the
    # entire thing in the calling process as one binary -- a spike the size of
    # the file per upload, several times that when a few land together.
    # `NervesHub.Firmwares.Upload.S3` already uploads this way.
    file_path
    |> S3.Upload.stream_file()
    |> S3.upload(bucket(), key, [timeout: @upload_timeout] ++ Keyword.take(opts, [:meta]))
    |> ExAws.request!()

    :ok
  end

  @impl NervesHub.Uploads
  def url(key, opts) do
    case Keyword.has_key?(opts, :signed) do
      true ->
        config = ExAws.Config.new(:s3)
        signed_opts = DownloadHost.presign_opts(opts[:signed])
        {:ok, url} = S3.presigned_url(config, :get, bucket(), key, signed_opts)
        DownloadHost.rewrite(url)

      false ->
        "https://s3.amazonaws.com/#{bucket()}#{key}"
    end
  end
end
