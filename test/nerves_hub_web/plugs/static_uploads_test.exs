defmodule NervesHubWeb.Plugs.StaticUploadsTest do
  use NervesHubWeb.ConnCase, async: false

  alias NervesHubWeb.Plugs.StaticUploads

  describe "init/1" do
    test "returns opts unchanged" do
      assert StaticUploads.init([]) == []
    end
  end

  describe "call/2 when uploads are disabled" do
    test "passes conn through unchanged" do
      original = Application.get_env(:nerves_hub, NervesHub.Uploads.File, [])
      Application.put_env(:nerves_hub, NervesHub.Uploads.File, enabled: false)
      on_exit(fn -> Application.put_env(:nerves_hub, NervesHub.Uploads.File, original) end)

      conn = build_conn()
      result = StaticUploads.call(conn, [])
      assert result == conn
    end
  end

  describe "call/2 when uploads are enabled" do
    test "delegates to Plug.Static and returns a conn" do
      original = Application.get_env(:nerves_hub, NervesHub.Uploads.File, [])

      Application.put_env(:nerves_hub, NervesHub.Uploads.File,
        enabled: true,
        public_path: "/uploads",
        local_path: System.tmp_dir!()
      )

      on_exit(fn -> Application.put_env(:nerves_hub, NervesHub.Uploads.File, original) end)

      conn = build_conn(:get, "/uploads/some-file.bin")
      result = StaticUploads.call(conn, [])
      assert %Plug.Conn{} = result
    end
  end
end
