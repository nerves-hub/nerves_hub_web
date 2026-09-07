defmodule NervesHub.ExtensionsTest do
  @moduledoc """
  What the platform tells devices it implements, and what it does with what
  they declare back.
  """
  use ExUnit.Case, async: false

  alias NervesHub.Extensions
  alias NervesHub.Extensions.Health
  alias NervesHub.Extensions.Logging
  alias NervesHub.Extensions.Unsupported

  setup do
    enabled = Application.get_env(:nerves_hub, :analytics_enabled)
    on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, enabled) end)

    Application.put_env(:nerves_hub, :analytics_enabled, true)

    :ok
  end

  describe "advertisement/0" do
    test "offers every version of every extension, newest first" do
      advertisement = Extensions.advertisement()

      assert advertisement["logging"] == ["0.1.0", "0.0.1"]
      assert advertisement["health"] == ["0.0.1"]
    end

    test "leaves out an extension this deployment has switched off" do
      # A device that is not told about logging does not buffer log lines for a
      # platform that would only throw them away.
      Application.put_env(:nerves_hub, :analytics_enabled, false)

      advertisement = Extensions.advertisement()

      refute Map.has_key?(advertisement, "logging")
      assert advertisement["health"] == ["0.0.1"]
    end

    test "every version offered is one a device can actually be served" do
      # The advertisement and the dispatch read the same table, and this is what
      # says so. An advertised version that resolved to `Unsupported` would have
      # the platform inviting devices to declare something it then refuses.
      for {key, versions} <- Extensions.advertisement(), version <- versions do
        module = Extensions.module(String.to_existing_atom(key), Version.parse!(version))

        refute module == Unsupported, "#{key} #{version} is advertised but not implemented"
      end
    end

    test "says the same thing as versions/1" do
      for {key, versions} <- Extensions.advertisement() do
        assert versions == Extensions.versions(String.to_existing_atom(key))
      end
    end
  end

  describe "module/2" do
    test "serves the version the device declared" do
      assert Extensions.module(:logging, Version.parse!("0.0.1")) == Logging
      assert Extensions.module(:logging, Version.parse!("0.1.0")) == Logging.Batched
      assert Extensions.module(:health, Version.parse!("0.0.1")) == Health
    end

    test "serves a device that predates the advertisement" do
      # It declared a patch version of its own rather than one this platform
      # names, which is why the table matches on a requirement and not on the
      # advertised string.
      assert Extensions.module(:logging, Version.parse!("0.0.5")) == Logging
    end

    test "refuses a version this platform does not implement" do
      assert Extensions.module(:logging, Version.parse!("0.2.0")) == Unsupported
      assert Extensions.module(:health, Version.parse!("1.0.0")) == Unsupported
    end

    test "refuses an extension it has never heard of" do
      assert Extensions.module(:telepathy, Version.parse!("0.0.1")) == Unsupported
    end
  end
end
