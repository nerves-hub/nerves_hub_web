defmodule NervesHub.Firmwares.UpdateToolGatingTest do
  @moduledoc """
  Which update tools an instance offers.

  Not async: every test here changes application environment, which is global.
  """
  use ExUnit.Case, async: false

  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Support.EspIdf

  describe "tool availability" do
    setup do
      original = Application.get_env(:nerves_hub, :esp_idf_firmware_enabled)
      on_exit(fn -> Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, original) end)
      :ok
    end

    test "fwup is always available" do
      Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, false)
      assert Map.keys(UpdateTool.all()) == ["fwup"]
    end

    # Accepting a format the platform cannot signature-verify has to be an
    # explicit choice, not something acquired by deploying a new version.
    test "esp-idf is only available when the platform enables it" do
      Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, false)
      refute Map.has_key?(UpdateTool.all(), "esp-idf")

      Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, true)
      assert Map.has_key?(UpdateTool.all(), "esp-idf")
    end

    test "an esp-idf image is not recognised while the tool is disabled", %{} do
      Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, false)

      path = Path.join(System.tmp_dir!(), "gated-#{System.unique_integer([:positive])}.bin")
      File.write!(path, EspIdf.image(product: "anything"))
      on_exit(fn -> File.rm(path) end)

      assert {:error, :unrecognised_firmware_format} = UpdateTool.for_file(path)
    end

    # The pre-registry config key pinned an instance to a single tool. Existing
    # deployments rely on it, so it has to keep winning over the defaults.
    test "the legacy :update_tool config still pins the instance to one tool" do
      Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, true)
      Application.put_env(:nerves_hub, :update_tool, UpdateTool.Fwup)
      on_exit(fn -> Application.delete_env(:nerves_hub, :update_tool) end)

      assert Map.keys(UpdateTool.all()) == ["fwup"]
    end
  end
end
