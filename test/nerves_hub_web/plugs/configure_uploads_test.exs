defmodule NervesHubWeb.Plugs.ConfigureUploadsTest do
  use NervesHubWeb.ConnCase, async: true

  alias NervesHub.Firmwares.Upload.S3
  alias NervesHubWeb.Plugs.ConfigureUploads

  describe "init/1" do
    test "returns opts unchanged" do
      assert ConfigureUploads.init([]) == []
    end
  end

  describe "call/2 when using S3 uploads (non-local)" do
    test "passes conn through unchanged" do
      original = Application.get_env(:nerves_hub, :firmware_upload)
      Application.put_env(:nerves_hub, :firmware_upload, S3)
      on_exit(fn -> Application.put_env(:nerves_hub, :firmware_upload, original) end)

      conn = build_conn()
      result = ConfigureUploads.call(conn, [])
      assert result == conn
    end
  end

  describe "call/2 when using local file uploads" do
    test "conn passes through (static plugs may halt or pass on)" do
      original_upload = Application.get_env(:nerves_hub, :firmware_upload)
      Application.put_env(:nerves_hub, :firmware_upload, NervesHub.Firmwares.Upload.File)
      on_exit(fn -> Application.put_env(:nerves_hub, :firmware_upload, original_upload) end)

      conn = build_conn(:get, "/")
      result = ConfigureUploads.call(conn, [])
      # The plug delegates to FileUpload + StaticUploads; result is a Plug.Conn
      assert %Plug.Conn{} = result
    end
  end
end
