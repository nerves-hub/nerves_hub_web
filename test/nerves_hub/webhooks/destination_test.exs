defmodule NervesHub.Webhooks.DestinationTest do
  use ExUnit.Case, async: true

  alias NervesHub.Webhooks.Destination

  @public [allow_private: false]
  @private [allow_private: true]

  describe "validate_url/2" do
    test "accepts http and https URLs with a host" do
      assert :ok = Destination.validate_url("https://example.com/hooks?source=nerves", @public)
      assert :ok = Destination.validate_url("http://example.com:8080/hooks", @public)
    end

    test "refuses other schemes, a missing host, and credentials in the URL" do
      assert {:error, "must start with https:// or http://"} = Destination.validate_url("ftp://example.com", @public)
      assert {:error, "must start with https:// or http://"} = Destination.validate_url("example.com/hooks", @public)
      assert {:error, "must include a host"} = Destination.validate_url("https:///hooks", @public)

      assert {:error, "must not include a username or password"} =
               Destination.validate_url("https://user:pass@example.com", @public)

      assert {:error, "is not a valid URL"} = Destination.validate_url("https://exa mple.com", @public)
    end

    test "refuses a literal private address unless private destinations are allowed" do
      for url <- ["http://127.0.0.1/hooks", "http://10.1.2.3", "http://169.254.169.254/latest", "http://[::1]:4000"] do
        assert {:error, "must not be a private or reserved address"} = Destination.validate_url(url, @public)
        assert :ok = Destination.validate_url(url, @private)
      end
    end
  end

  describe "allowed?/2" do
    test "allows public addresses" do
      for address <- [{93, 184, 216, 34}, {8, 8, 8, 8}, {0x2606, 0x2800, 0x220, 0x1, 0x248, 0x1893, 0x25C8, 0x1946}] do
        assert Destination.allowed?(address, @public), "expected #{:inet.ntoa(address)} to be allowed"
      end
    end

    test "refuses loopback, private, link-local, CGNAT, multicast and reserved addresses" do
      addresses = [
        {0, 0, 0, 0},
        {127, 0, 0, 1},
        {10, 0, 0, 1},
        {172, 16, 0, 1},
        {172, 31, 255, 255},
        {192, 168, 1, 1},
        {169, 254, 169, 254},
        {100, 64, 0, 1},
        {224, 0, 0, 1},
        {255, 255, 255, 255},
        {0, 0, 0, 0, 0, 0, 0, 1},
        {0, 0, 0, 0, 0, 0, 0, 0},
        {0xFC00, 0, 0, 0, 0, 0, 0, 1},
        {0xFE80, 0, 0, 0, 0, 0, 0, 1},
        {0xFF02, 0, 0, 0, 0, 0, 0, 1}
      ]

      for address <- addresses do
        refute Destination.allowed?(address, @public), "expected #{:inet.ntoa(address)} to be refused"
        assert Destination.allowed?(address, @private)
      end
    end

    test "refuses IPv6 addresses that carry a private IPv4 address, and allows those that carry a public one" do
      # ::ffff:127.0.0.1, 64:ff9b::10.0.0.1 and 2002:a9fe:a9fe:: (6to4 for 169.254.169.254)
      refute Destination.allowed?({0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 0x0001}, @public)
      refute Destination.allowed?({0x64, 0xFF9B, 0, 0, 0, 0, 0x0A00, 0x0001}, @public)
      refute Destination.allowed?({0x2002, 0xA9FE, 0xA9FE, 0, 0, 0, 0, 0}, @public)

      # ::ffff:8.8.8.8
      assert Destination.allowed?({0, 0, 0, 0, 0, 0xFFFF, 0x0808, 0x0808}, @public)
    end
  end

  describe "resolve/2" do
    test "connects by name when private destinations are allowed" do
      assert {:ok, nil} = Destination.resolve("https://localhost/hooks", @private)
    end

    test "returns the checked address for a public literal" do
      assert {:ok, {93, 184, 216, 34}} = Destination.resolve("https://93.184.216.34/hooks", @public)
    end

    test "refuses a name that resolves to a private address" do
      assert {:error, "localhost resolves to a private or reserved address"} =
               Destination.resolve("http://localhost:4000/hooks", @public)
    end

    test "refuses a literal private address" do
      assert {:error, "169.254.169.254 resolves to a private or reserved address"} =
               Destination.resolve("http://169.254.169.254/latest/meta-data", @public)
    end
  end
end
