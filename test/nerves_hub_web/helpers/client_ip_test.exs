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

    test "takes the rightmost value, which is the one the balancer appended" do
      # What a device claiming to be somewhere else produces: its own value is
      # still there, but everything the balancer saw comes after it.
      connect_info = connect_info({10, 0, 0, 1}, [{@header, "198.51.100.2, 203.0.113.7"}])

      assert "203.0.113.7" == ClientIP.resolve(connect_info, @header)
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
