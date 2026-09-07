defmodule NervesHubWeb.Plugs.FileUploadTest do
  use NervesHubWeb.ConnCase, async: false

  alias NervesHubWeb.Plugs.FileUpload

  describe "init/1" do
    test "returns opts unchanged" do
      assert FileUpload.init([]) == []
    end
  end

  describe "call/2 when file upload is disabled" do
    test "passes conn through unchanged" do
      original = Application.get_env(:nerves_hub, NervesHub.Firmwares.Upload.File, [])
      Application.put_env(:nerves_hub, NervesHub.Firmwares.Upload.File, enabled: false)
      on_exit(fn -> Application.put_env(:nerves_hub, NervesHub.Firmwares.Upload.File, original) end)

      conn = build_conn()
      result = FileUpload.call(conn, [])
      assert result == conn
    end
  end

  describe "call/2 when file upload is enabled" do
    test "delegates to Plug.Static and returns a conn" do
      original = Application.get_env(:nerves_hub, NervesHub.Firmwares.Upload.File, [])

      Application.put_env(:nerves_hub, NervesHub.Firmwares.Upload.File,
        enabled: true,
        public_path: "/firmware",
        local_path: System.tmp_dir!()
      )

      on_exit(fn -> Application.put_env(:nerves_hub, NervesHub.Firmwares.Upload.File, original) end)

      conn = build_conn(:get, "/firmware/nonexistent.fw")
      result = FileUpload.call(conn, [])
      assert %Plug.Conn{} = result
    end
  end
end
