defmodule NervesHub.Firmwares.Upload.FileTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Firmwares.Upload.File

  describe "metadata/2" do
    test "builds local and public path for file" do
      config = Application.get_env(:nerves_hub, File)
      %{local_path: local_path, public_path: public_path} = File.metadata(11, "firmware.fw")

      assert local_path == "#{config[:local_path]}11/firmware.fw"
      assert public_path == "http://localhost:1234/firmware/11/firmware.fw"
    end
  end
end
