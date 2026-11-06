defmodule NervesHub.Devices.ClientLibraryTest do
  use ExUnit.Case, async: true

  import NervesHub.Devices.ClientLibrary, only: [from_user_agent: 1]

  alias NervesHub.Devices.ClientLibrary

  doctest ClientLibrary

  @unknown %{lib: nil, lib_version: nil}

  describe "from_user_agent/1 with a listed client" do
    test "records each under its own name" do
      assert from_user_agent("NHL/2.13.0") == %{lib: "nerves_hub_link", lib_version: "2.13.0"}

      assert from_user_agent("nerves-hub-link-agent/0.1.0") ==
               %{lib: "nerves_hub_link_agent", lib_version: "0.1.0"}

      assert from_user_agent("nerves-hub-link-esp32/0.1.0") ==
               %{lib: "nerves_hub_link_esp32", lib_version: "0.1.0"}

      assert from_user_agent("nerves_hub_link_atomvm_esp32/0.2.0") ==
               %{lib: "nerves_hub_link_atomvm_esp32", lib_version: "0.2.0"}
    end

    test "records NervesHubLink the same whichever of its tokens it sends" do
      assert from_user_agent("nerves_hub_link/2.13.0") == from_user_agent("NHL/2.13.0")
    end

    test "keeps pre-release and build metadata in the version" do
      assert from_user_agent("NHL/2.13.0-rc.1+build.7") ==
               %{lib: "nerves_hub_link", lib_version: "2.13.0-rc.1+build.7"}
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

  describe "from_user_agent/1 with any other client" do
    test "records it under the name it sends" do
      assert from_user_agent("acme-link/1.4.0") == %{lib: "acme-link", lib_version: "1.4.0"}
      assert from_user_agent("Acme_Link.v2/0.0.1-beta") == %{lib: "Acme_Link.v2", lib_version: "0.0.1-beta"}
    end

    test "matches listed names exactly, so a near miss is a client of its own" do
      assert from_user_agent("nhl/2.13.0") == %{lib: "nhl", lib_version: "2.13.0"}
    end

    test "is unknown without a SemVer version" do
      assert from_user_agent("acme-link") == @unknown
      assert from_user_agent("acme-link/") == @unknown
      assert from_user_agent("acme-link/1.4") == @unknown
      assert from_user_agent("acme-link/v1.4.0") == @unknown
      assert from_user_agent("acme-link/1.4.0-" <> String.duplicate("a", 64)) == @unknown
    end

    test "is unknown for a name outside the limits" do
      assert from_user_agent("acme@link/1.4.0") == @unknown
      assert from_user_agent(".acme-link/1.4.0") == @unknown
      assert from_user_agent(String.duplicate("a", 65) <> "/1.4.0") == @unknown

      assert from_user_agent(String.duplicate("a", 64) <> "/1.4.0") ==
               %{lib: String.duplicate("a", 64), lib_version: "1.4.0"}
    end
  end

  describe "from_user_agent/1 with no client named" do
    test "is unknown without a header" do
      assert from_user_agent(nil) == @unknown
      assert from_user_agent("") == @unknown
    end

    test "is unknown for what HTTP libraries send by default" do
      assert from_user_agent("ESP32 Websocket Client") == @unknown
      assert from_user_agent("Go-http-client/1.1") == @unknown
      assert from_user_agent("Python/3.11 websockets/12.0") == @unknown
      assert from_user_agent("Mozilla/5.0 (X11; Linux x86_64)") == @unknown
    end

    # Every NervesHubLink that doesn't send its own token sends Mint's.
    test "is unknown for an HTTP library's default even with a SemVer version" do
      assert from_user_agent("mint/1.7.1") == @unknown
      assert from_user_agent("Mint/1.7.1") == @unknown
      assert from_user_agent("okhttp/4.12.0") == @unknown
      assert from_user_agent("Java-http-client/21.0.1") == @unknown
      assert from_user_agent("Python/3.11 aiohttp/3.9.1") == @unknown
      assert from_user_agent("curl/8.4.0") == @unknown
    end
  end

  describe "from_user_agent/1 with several tokens" do
    test "takes the first that names a client" do
      assert from_user_agent("NHL/2.13.0 Mint/1.7.1") == %{lib: "nerves_hub_link", lib_version: "2.13.0"}
      assert from_user_agent("acme-link/1.4.0 NHL/2.13.0") == %{lib: "acme-link", lib_version: "1.4.0"}
      assert from_user_agent("Go-http-client/1.1 acme-link/1.4.0") == %{lib: "acme-link", lib_version: "1.4.0"}
      assert from_user_agent("mint/1.7.1 acme-link/1.4.0") == %{lib: "acme-link", lib_version: "1.4.0"}
    end

    test "skips tokens inside comments" do
      assert from_user_agent("Other/1.0 (compatible; NHL/2.13.0)") == @unknown
      assert from_user_agent("Other/1.0 (outer (NHL/2.13.0) more)") == @unknown

      assert from_user_agent("nerves-hub-link-esp32/0.1.0 (esp-idf 5.2.3)") ==
               %{lib: "nerves_hub_link_esp32", lib_version: "0.1.0"}
    end
  end
end
