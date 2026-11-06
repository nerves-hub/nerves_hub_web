defmodule NervesHub.Devices.ClientLibraryTest do
  use ExUnit.Case, async: true

  import NervesHub.Devices.ClientLibrary, only: [from_user_agent: 1]

  alias NervesHub.Devices.ClientLibrary

  doctest ClientLibrary

  @unknown %{lib: nil, lib_version: nil}

  describe "from_user_agent/1" do
    test "recognises each client library by its product token" do
      assert from_user_agent("NHL/2.13.0") == %{lib: "nerves_hub_link", lib_version: "2.13.0"}

      assert from_user_agent("nerves-hub-link-agent/0.1.0") ==
               %{lib: "nerves_hub_link_agent", lib_version: "0.1.0"}

      assert from_user_agent("nerves-hub-link-esp32/0.1.0") ==
               %{lib: "nerves_hub_link_esp32", lib_version: "0.1.0"}

      assert from_user_agent("nerves_hub_link_atomvm_esp32/0.2.0") ==
               %{lib: "nerves_hub_link_atomvm_esp32", lib_version: "0.2.0"}
    end

    test "keeps pre-release and build metadata in the version" do
      assert from_user_agent("NHL/2.13.0-rc.1+build.7") ==
               %{lib: "nerves_hub_link", lib_version: "2.13.0-rc.1+build.7"}
    end

    test "is unknown without a header" do
      assert from_user_agent(nil) == @unknown
      assert from_user_agent("") == @unknown
    end

    test "is unknown for a client it doesn't list" do
      assert from_user_agent("curl/8.4.0") == @unknown
      assert from_user_agent("Mozilla/5.0 (X11; Linux x86_64)") == @unknown
    end

    test "is unknown for esp_websocket_client's default" do
      assert from_user_agent("ESP32 Websocket Client") == @unknown
    end

    test "matches product names exactly" do
      assert from_user_agent("nhl/2.13.0") == @unknown
      assert from_user_agent("NHLX/2.13.0") == @unknown
    end

    test "takes the first listed token, after any it doesn't list" do
      assert from_user_agent("NHL/2.13.0 Mint/1.7.1") == %{lib: "nerves_hub_link", lib_version: "2.13.0"}
      assert from_user_agent("Mint/1.7.1 NHL/2.13.0") == %{lib: "nerves_hub_link", lib_version: "2.13.0"}

      assert from_user_agent("NHL/2.13.0 nerves-hub-link-agent/0.1.0") ==
               %{lib: "nerves_hub_link", lib_version: "2.13.0"}
    end

    test "skips tokens inside comments" do
      assert from_user_agent("Other/1.0 (compatible; NHL/2.13.0)") == @unknown
      assert from_user_agent("Other/1.0 (outer (NHL/2.13.0) more)") == @unknown

      assert from_user_agent("nerves-hub-link-esp32/0.1.0 (esp-idf 5.2.3)") ==
               %{lib: "nerves_hub_link_esp32", lib_version: "0.1.0"}
    end

    test "records the library without a version it can't read" do
      assert from_user_agent("NHL") == %{lib: "nerves_hub_link", lib_version: nil}
      assert from_user_agent("NHL/") == %{lib: "nerves_hub_link", lib_version: nil}
      assert from_user_agent("NHL/2.13") == %{lib: "nerves_hub_link", lib_version: nil}
      assert from_user_agent("NHL/v2.13.0") == %{lib: "nerves_hub_link", lib_version: nil}
    end

    test "records no version longer than a real one" do
      long = "2.13.0-" <> String.duplicate("a", 64)

      assert {:ok, _version} = Version.parse(long)
      assert from_user_agent("NHL/" <> long) == %{lib: "nerves_hub_link", lib_version: nil}
    end
  end
end
