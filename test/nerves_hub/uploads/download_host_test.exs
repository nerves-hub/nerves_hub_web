defmodule NervesHub.Uploads.DownloadHostTest do
  # Not async: these move :s3_download_host, which every presign reads.
  use ExUnit.Case, async: false

  alias NervesHub.Firmwares.Upload.S3, as: FirmwareUpload
  alias NervesHub.Uploads.DownloadHost

  @bucket "mybucket"
  @key "firmware/1/abcdef.fw"
  # NervesHub.Firmwares.Upload.S3 signs firmware URLs for a day.
  @validity 60 * 60 * 24

  setup context do
    Application.put_env(:ex_aws, :s3,
      access_key_id: "AKIAEXAMPLE",
      secret_access_key: "s3cret",
      region: "fr-par",
      host: "s3.fr-par.scw.cloud"
    )

    Application.put_env(:nerves_hub, FirmwareUpload, bucket: @bucket, presigned_url_opts: [])

    if host = context[:download_host] do
      Application.put_env(:nerves_hub, :s3_download_host, host)
    end

    on_exit(fn ->
      Application.delete_env(:ex_aws, :s3)
      Application.delete_env(:nerves_hub, FirmwareUpload)
      Application.delete_env(:nerves_hub, :s3_download_host)
    end)

    :ok
  end

  describe "with no download host configured" do
    test "rewrite/1 leaves the URL alone" do
      url = "https://#{@bucket}.s3.fr-par.scw.cloud/#{@key}?X-Amz-Signature=abc"
      assert DownloadHost.rewrite(url) == url
    end

    test "presign_opts/1 leaves the options alone" do
      assert DownloadHost.presign_opts(expires_in: 60) == [expires_in: 60]
    end

    test "download_file/1 serves from the bucket's own endpoint" do
      {:ok, url} = FirmwareUpload.download_file(firmware())
      assert URI.parse(url).host == "s3.fr-par.scw.cloud"
    end
  end

  describe "with a download host configured" do
    @describetag download_host: "firmware.example.com"

    test "rewrite/1 replaces the host and keeps everything that is signed" do
      url = "https://#{@bucket}.s3.fr-par.scw.cloud/#{@key}?X-Amz-Signature=abc&X-Amz-Expires=60"
      rewritten = DownloadHost.rewrite(url)

      assert rewritten ==
               "https://firmware.example.com/#{@key}?X-Amz-Signature=abc&X-Amz-Expires=60"
    end

    test "presign_opts/1 asks for virtual-hosted addressing" do
      opts = DownloadHost.presign_opts(expires_in: 60)

      assert opts[:virtual_host] == true
      assert opts[:expires_in] == 60
    end

    test "download_file/1 hands out our host with the bucket in neither host nor path" do
      {:ok, url} = FirmwareUpload.download_file(firmware())
      uri = URI.parse(url)

      assert uri.scheme == "https"
      assert uri.host == "firmware.example.com"
      # Path style would be "/mybucket/firmware/...", and a proxy in front of
      # the bucket serves the key at the root.
      assert uri.path == "/#{@key}"
    end

    test "download_file/1 signs for the bucket, not for our host" do
      {:ok, url} = FirmwareUpload.download_file(firmware())
      uri = URI.parse(url)

      # Rebuild the same signature from the timestamp the URL carries. It only
      # matches if the canonical request named the bucket's virtual-hosted
      # endpoint, which is what a proxy sends upstream. Signing for
      # firmware.example.com gives the bucket SignatureDoesNotMatch.
      signed_at = signed_at(uri)

      {:ok, expected} =
        ExAws.S3.presigned_url(ExAws.Config.new(:s3), :get, @bucket, @key,
          expires_in: @validity,
          virtual_host: true,
          start_datetime: signed_at
        )

      assert URI.parse(expected).host == "#{@bucket}.s3.fr-par.scw.cloud"
      assert URI.parse(expected).query == uri.query
    end
  end

  defp firmware(), do: %{upload_metadata: %{"s3_key" => @key}}

  # "20260101T000000Z" -> ~N[2026-01-01 00:00:00]
  defp signed_at(uri) do
    <<year::binary-4, month::binary-2, day::binary-2, "T", hour::binary-2, minute::binary-2, second::binary-2, "Z">> =
      uri.query |> URI.decode_query() |> Map.fetch!("X-Amz-Date")

    [year, month, day, hour, minute, second]
    |> Enum.map(&String.to_integer/1)
    |> then(fn [y, mo, d, h, mi, s] -> NaiveDateTime.new!(y, mo, d, h, mi, s) end)
  end
end
