defmodule NervesHub.Firmwares.UpdateToolGatingTest do
  @moduledoc """
  Which update tools an instance offers.

  Not async: every test here changes application environment, which is global.
  """
  use ExUnit.Case, async: false

  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Support.AtomVM, as: AtomVMBuilder
  alias NervesHub.Support.EspIdf

  describe "tool availability" do
    setup do
      original = Application.get_env(:nerves_hub, :esp_idf_firmware_enabled)
      original_atomvm = Application.get_env(:nerves_hub, :atomvm_firmware_enabled)

      on_exit(fn ->
        Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, original)
        Application.put_env(:nerves_hub, :atomvm_firmware_enabled, original_atomvm)
      end)

      :ok
    end

    test "fwup is always available" do
      Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, false)
      Application.put_env(:nerves_hub, :atomvm_firmware_enabled, false)
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

    # Packbeam carries no signature at all, so accepting it is a decision about
    # an instance's trust model rather than a default.
    test "atomvm is only available when the platform enables it" do
      Application.put_env(:nerves_hub, :atomvm_firmware_enabled, false)
      refute Map.has_key?(UpdateTool.all(), "atomvm")

      Application.put_env(:nerves_hub, :atomvm_firmware_enabled, true)
      assert Map.has_key?(UpdateTool.all(), "atomvm")
    end

    # Building the available map out of `known/0` would mean turning one format
    # on turned every format on.
    test "each format is gated on its own flag" do
      Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, true)
      Application.put_env(:nerves_hub, :atomvm_firmware_enabled, false)

      assert Map.has_key?(UpdateTool.all(), "esp-idf")
      refute Map.has_key?(UpdateTool.all(), "atomvm")

      Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, false)
      Application.put_env(:nerves_hub, :atomvm_firmware_enabled, true)

      refute Map.has_key?(UpdateTool.all(), "esp-idf")
      assert Map.has_key?(UpdateTool.all(), "atomvm")
    end

    test "a packbeam is not recognised while the tool is disabled" do
      Application.put_env(:nerves_hub, :atomvm_firmware_enabled, false)

      path = Path.join(System.tmp_dir!(), "gated-#{System.unique_integer([:positive])}.avm")
      File.write!(path, AtomVMBuilder.packbeam(product: "anything"))
      on_exit(fn -> File.rm(path) end)

      assert {:error, :unrecognised_firmware_format} = UpdateTool.for_file(path)

      Application.put_env(:nerves_hub, :atomvm_firmware_enabled, true)
      assert {:ok, UpdateTool.AtomVM} = UpdateTool.for_file(path)
    end

    # Firmware already uploaded has to stay readable after a format is turned
    # off again, or disabling the flag would orphan it.
    test "every format stays known whether or not it is enabled" do
      Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, false)
      Application.put_env(:nerves_hub, :atomvm_firmware_enabled, false)

      assert Enum.sort(Map.keys(UpdateTool.known())) == ["atomvm", "esp-idf", "fwup"]
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
