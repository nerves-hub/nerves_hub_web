defmodule NervesHub.Workers.DeleteFirmwareTest do
  use NervesHub.DataCase, async: true
  use Mimic

  alias NervesHub.Firmwares.Upload.File, as: UploadFile
  alias NervesHub.Workers.DeleteFirmware

  describe "perform/1" do
    test "calls the firmware uploader's delete_file with the job args" do
      args = %{"local_path" => "/some/firmware/path.fw"}

      stub(UploadFile, :delete_file, fn received_args ->
        assert received_args == args
        :ok
      end)

      job = %Oban.Job{args: args}
      assert :ok = DeleteFirmware.perform(job)
    end

    test "returns the result from delete_file" do
      stub(UploadFile, :delete_file, fn _args -> {:error, :enoent} end)

      job = %Oban.Job{args: %{"local_path" => "/missing/path.fw"}}
      assert {:error, :enoent} = DeleteFirmware.perform(job)
    end
  end
end
