defmodule NervesHubWeb.DynamicConfigMultipartTest do
  use NervesHubWeb.APIConnCase

  alias NervesHubWeb.DynamicConfigMultipart

  @reasonable_size 100
  @firmware_size 1_000_001

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
      # bring max_size down so it doesn't make a huge file
      config = Application.get_env(:nerves_hub, NervesHub.Firmwares.Upload, [])
      :ok = Application.put_env(:nerves_hub, NervesHub.Firmwares.Upload, max_size: 100)

      # reset the config after we're done
      on_exit(fn ->
        Application.put_env(:nerves_hub, NervesHub.Firmwares.Upload, config)
      end)

      assert_raise Plug.Parsers.RequestTooLargeError, fn ->
        upload_multipart_file("/api/orgs/acme/products/anvil/firmwares", 101)
      end
    end
  end

  def upload_multipart_file(path, filesize) do
    # create an instance of the parser
    parser = Plug.Parsers.init(parsers: [DynamicConfigMultipart], pass: ["*/*"])

    # create a multipart payload matching the given filesize
    {body, boundary} = multipart_file(filesize)

    # run it through our parser
    Plug.Test.conn(:post, path, body)
    |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
    |> Plug.Parsers.call(parser)
  end

  defp multipart_file(size) do
    large_content = String.duplicate("a", size)

    boundary = "----TestBoundary123"

    body = """
    --#{boundary}\r
    Content-Disposition: form-data; name="title"\r
    \r
    Test Upload\r
    --#{boundary}\r
    Content-Disposition: form-data; name="file"; filename="large.txt"\r
    Content-Type: text/plain\r
    \r
    #{large_content}\r
    --#{boundary}--\r
    """

    {body, boundary}
  end
end
