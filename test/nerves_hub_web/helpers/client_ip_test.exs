defmodule NervesHubWeb.Helpers.ClientIPTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.Helpers.ClientIP

  @header "x-forwarded-for"

  describe "an endpoint that trusts no header" do
    test "reports the socket's peer" do
      assert "203.0.113.7" == ClientIP.resolve(connect_info({203, 0, 113, 7}))
    end

    test "ignores a forwarded header the device sent anyway" do
      connect_info = connect_info({203, 0, 113, 7}, [{@header, "198.51.100.2"}])

      assert "203.0.113.7" == ClientIP.resolve(connect_info)
    end

    test "reports nothing when the socket has no peer" do
      assert nil == ClientIP.resolve(%{x_headers: []})
    end
  end

  describe "an endpoint that trusts a header" do
    test "reports the address the balancer announced rather than the balancer" do
      connect_info = connect_info({10, 0, 0, 1}, [{@header, "203.0.113.7"}])

      assert "203.0.113.7" == ClientIP.resolve(connect_info, @header)
    end

    test "takes the rightmost value when nothing was appended past the device" do
      # What a device claiming to be somewhere else produces: its own value is
      # still there, but what the proxy saw comes after it.
      connect_info = connect_info({10, 0, 0, 1}, [{@header, "198.51.100.2, 203.0.113.7"}])

      assert "203.0.113.7" == ClientIP.resolve(connect_info, @header)
    end

    test "skips the entries the infrastructure appended past the device" do
      # The shape Fly.io produces: the address it observed, then the app's own
      # anycast address. Taking the rightmost would record the app for every
      # device in the fleet.
      connect_info = connect_info({10, 0, 0, 1}, [{@header, "203.0.113.7, 66.241.125.59"}])

      assert "203.0.113.7" == ClientIP.resolve(connect_info, @header, 1)
    end

    test "a device cannot shift which entry is read by forging its own" do
      # Prepending values only pushes the list leftwards. The two entries Fly
      # appends stay at the end, so the count still lands on the device.
      forged = connect_info({10, 0, 0, 1}, [{@header, "1.2.3.4, 203.0.113.7, 66.241.125.59"}])
      piled_on = connect_info({10, 0, 0, 1}, [{@header, "1.2.3.4, 5.6.7.8, 203.0.113.7, 66.241.125.59"}])

      assert "203.0.113.7" == ClientIP.resolve(forged, @header, 1)
      assert "203.0.113.7" == ClientIP.resolve(piled_on, @header, 1)
    end

    test "falls back to the socket when the header holds fewer entries than the count" do
      connect_info = connect_info({10, 0, 0, 1}, [{@header, "66.241.125.59"}])

      assert "10.0.0.1" == ClientIP.resolve(connect_info, @header, 1)
    end

    test "takes the rightmost value across repeated headers" do
      connect_info =
        connect_info({10, 0, 0, 1}, [{@header, "198.51.100.2"}, {@header, "203.0.113.7"}])

      assert "203.0.113.7" == ClientIP.resolve(connect_info, @header)
    end

    test "reads an IPv6 address" do
      connect_info = connect_info({10, 0, 0, 1}, [{@header, "2001:db8::1"}])

      assert "2001:db8::1" == ClientIP.resolve(connect_info, @header)
    end

    test "unwraps an IPv4 address announced inside the v4-mapped range" do
      connect_info = connect_info({10, 0, 0, 1}, [{@header, "::ffff:203.0.113.7"}])

      assert "203.0.113.7" == ClientIP.resolve(connect_info, @header)
    end

    test "drops a port the balancer appended to the address" do
      connect_info = connect_info({10, 0, 0, 1}, [{@header, "203.0.113.7:51234"}])

      assert "203.0.113.7" == ClientIP.resolve(connect_info, @header)
    end

    test "drops a port appended to a bracketed IPv6 address" do
      connect_info = connect_info({10, 0, 0, 1}, [{@header, "[2001:db8::1]:51234"}])

      assert "2001:db8::1" == ClientIP.resolve(connect_info, @header)
    end

    test "falls back to the socket's peer when the header is absent" do
      assert "10.0.0.1" == ClientIP.resolve(connect_info({10, 0, 0, 1}), @header)
    end

    test "falls back to the socket's peer when the header isn't an address" do
      connect_info = connect_info({10, 0, 0, 1}, [{@header, "unknown"}])

      assert "10.0.0.1" == ClientIP.resolve(connect_info, @header)
    end

    test "falls back to the socket's peer when the header is empty" do
      connect_info = connect_info({10, 0, 0, 1}, [{@header, ", "}])

      assert "10.0.0.1" == ClientIP.resolve(connect_info, @header)
    end

    test "ignores headers that aren't the one trusted" do
      connect_info = connect_info({10, 0, 0, 1}, [{"x-real-ip", "203.0.113.7"}])

      assert "10.0.0.1" == ClientIP.resolve(connect_info, @header)
    end
  end

  defp connect_info(address, x_headers \\ []) do
    %{peer_data: %{address: address, port: 51_234, ssl_cert: nil}, x_headers: x_headers}
  end
end
