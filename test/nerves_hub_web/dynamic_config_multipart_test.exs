defmodule NervesHubWeb.DynamicConfigMultipartTest do
  use NervesHubWeb.APIConnCase

  alias NervesHubWeb.DynamicConfigMultipart

  @reasonable_size 1000
  @max_default_size 1024

  @firmware_size 2000
  @max_firmware_size 2048

  test "default options" do
    opts = DynamicConfigMultipart.init([])
    assert Keyword.fetch!(opts, :max_default_size) == 1_000_000
    assert Keyword.fetch!(opts, :max_firmware_size) == 200_000_000
  end

  describe "non-firmware paths" do
    test "allows resonably sized file through" do
      upload_multipart_file("/somewhere/over/the/rainbow", @reasonable_size)
    end

    test "returns :too_large error when body exceeds length limit" do
      assert_raise Plug.Parsers.RequestTooLargeError, fn ->
        upload_multipart_file("/somewhere/over/the/rainbow", @firmware_size)
      end
    end
  end

  describe "firmware" do
    test "allows firmware sized file through" do
      upload_multipart_file("/api/orgs/acme/products/anvil/firmwares", @firmware_size)
    end

    test "allows firmware sized file through when path contains spaces" do
      upload_multipart_file("/api/orgs/acme/products/big%20anvil/firmwares", @firmware_size)
    end

    test "returns :too_large error when multipart body exceeds the firmware limit" do
      assert_raise Plug.Parsers.RequestTooLargeError, fn ->
        upload_multipart_file("/api/orgs/acme/products/anvil/firmwares", 4096)
      end
    end
  end

  def upload_multipart_file(path, filesize) do
    # create an instance of the parser,
    # we shrink the sizes down so we don't have to generate huge files
    parser =
      {DynamicConfigMultipart,
       max_default_size: @max_default_size, max_firmware_size: @max_firmware_size}

    parsers = Plug.Parsers.init(parsers: [parser], pass: ["*/*"])

    # create a multipart payload matching the given filesize
    {body, boundary} = multipart_file(filesize)

    # run it through our parser
    Plug.Test.conn(:post, path, body)
    |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
    |> Plug.Parsers.call(parsers)
  end

  defp multipart_file(size) do
    large_content = String.duplicate("a", size)

    boundary = "----TestBoundary123"

    body = """
    --#{boundary}\r
    Content-Disposition: form-data; name="file"; filename="larger.txt"\r
    Content-Type: text/plain\r
    \r
    #{large_content}\r
    --#{boundary}--\r
    """

    {body, boundary}
  end
end
