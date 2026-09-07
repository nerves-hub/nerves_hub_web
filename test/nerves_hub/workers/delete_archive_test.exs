defmodule NervesHub.Workers.DeleteArchiveTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias NervesHub.Uploads
  alias NervesHub.Workers.DeleteArchive

  describe "perform/1" do
    test "calls Uploads.delete with the archive path" do
      stub(Uploads, :delete, fn path ->
        assert path == "some/archive/path.fw"
        :ok
      end)

      job = %Oban.Job{args: %{"archive_path" => "some/archive/path.fw"}}
      assert :ok = DeleteArchive.perform(job)
    end

    test "returns the result from Uploads.delete" do
      stub(Uploads, :delete, fn _path -> {:error, :not_found} end)

      job = %Oban.Job{args: %{"archive_path" => "missing/path.fw"}}
      assert {:error, :not_found} = DeleteArchive.perform(job)
    end
  end
end
