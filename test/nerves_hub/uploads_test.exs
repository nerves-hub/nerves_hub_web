defmodule NervesHub.UploadsTest do
  use ExUnit.Case, async: true

  alias NervesHub.Uploads
  alias NervesHub.Uploads.File, as: FileBackend

  describe "NervesHub.Uploads dispatcher" do
    test "backend/0 returns the configured backend module" do
      assert Uploads.backend() == NervesHub.Uploads.File
    end

    test "upload/3 delegates to the file backend" do
      tmp = System.tmp_dir()
      src = Path.join(tmp, "uploads_test_src_#{:rand.uniform(100_000)}.bin")
      key = "uploads_test_key_#{:rand.uniform(100_000)}"

      try do
        File.write!(src, "hello uploads")
        assert :ok = Uploads.upload(src, key)
      after
        File.rm(src)
        File.rm(Path.join(FileBackend.local_path(), key))
      end
    end

    test "url/2 delegates to the file backend" do
      key = "some/test/key.bin"
      url = Uploads.url(key, [])
      assert is_binary(url)
      assert String.contains?(url, "test/key.bin")
    end

    test "delete/1 delegates to the file backend" do
      tmp = System.tmp_dir()
      src = Path.join(tmp, "uploads_test_del_#{:rand.uniform(100_000)}.bin")
      key = "uploads_test_del_key_#{:rand.uniform(100_000)}"

      try do
        File.write!(src, "to delete")
        :ok = Uploads.upload(src, key)
        assert :ok = Uploads.delete(key)
      after
        File.rm(src)
      end
    end
  end

  describe "NervesHub.Uploads.File" do
    setup do
      key = "file_backend_test_#{:rand.uniform(100_000)}"
      tmp = System.tmp_dir()
      src = Path.join(tmp, "#{key}_src.bin")
      File.write!(src, "file backend test content")
      on_exit(fn -> File.rm(src) end)
      %{key: key, src: src}
    end

    test "upload/3 copies the file to local_path", %{key: key, src: src} do
      assert :ok = FileBackend.upload(src, key, [])
      dest = Path.join(FileBackend.local_path(), key)
      assert File.exists?(dest)
      File.rm(dest)
    end

    test "delete/1 removes the file from local_path", %{key: key, src: src} do
      :ok = FileBackend.upload(src, key, [])
      assert :ok = FileBackend.delete(key)
      dest = Path.join(FileBackend.local_path(), key)
      refute File.exists?(dest)
    end

    test "url/2 builds a URL from the endpoint config", %{key: key} do
      url = FileBackend.url(key, [])
      assert is_binary(url)
      assert String.contains?(url, key)
    end

    test "url/2 strips a leading slash from the key", %{key: key} do
      url_no_slash = FileBackend.url(key, [])
      url_slash = FileBackend.url("/" <> key, [])
      assert url_no_slash == url_slash
    end
  end
end
