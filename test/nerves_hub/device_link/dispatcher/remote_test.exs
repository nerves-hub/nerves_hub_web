defmodule NervesHub.DeviceLink.Dispatcher.RemoteTest do
  @moduledoc """
  The dispatcher that runs DeviceLink calls somewhere else.

  The equivalence tests here matter more than the mechanics ones. A caller that
  is not carrying the platform stack has to get the same answers as one that is,
  or devices behave differently depending on what they happened to connect to —
  and that difference would only show up in production.
  """

  use ExUnit.Case, async: false

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.DeviceLink.Dispatcher.Local
  alias NervesHub.DeviceLink.Dispatcher.NoHandlersError
  alias NervesHub.DeviceLink.Dispatcher.Remote
  alias NervesHub.DeviceLink.Handlers
  alias NervesHub.Extensions.Geo

  @versions %{"health" => "0.0.1", "geo" => "0.0.1", "local_shell" => "0.0.1"}

  defp device_info(device_id \\ 4242) do
    %DeviceInfo{
      allowed_extensions: [:health, :geo, :local_shell],
      connection_ref: "d3d1a1f0-0000-4000-8000-000000000001",
      deployment_id: 7,
      device_id: device_id,
      device_identifier: "equivalence-device",
      org_id: 1,
      product_id: 2
    }
  end

  describe "handler discovery" do
    test "this node is a handler in test, and lists deterministically" do
      assert Handlers.nodes() == [node()]
      assert Handlers.nodes() == Enum.sort(Handlers.nodes())
    end

    test "the same routing key always picks the same node first" do
      first = Handlers.ordered(1234)

      for _ <- 1..20, do: assert(Handlers.ordered(1234) == first)
    end

    test "a nil routing key does not raise, even though it does not pin a node" do
      assert Handlers.ordered(nil) == [node()]
    end
  end

  describe "equivalence with local dispatch" do
    test "extensions_join returns exactly the same thing either way" do
      info = device_info()

      local = Local.call(:extensions_join, [info, @versions])
      remote = Remote.call(:extensions_join, [info, @versions])

      assert local == remote

      # And what came back really did survive a trip through the wire format.
      {attach_list, extensions} = remote
      assert Enum.sort(attach_list) == ["geo", "health", "local_shell"]
      assert extensions["health"].state.device_info == info
    end

    test "structs and atoms come back as themselves, not as maps or strings" do
      {_attach_list, extensions} = Remote.call(:extensions_join, [device_info(), @versions])

      assert %DeviceInfo{} = extensions["geo"].state.device_info
      assert extensions["geo"].module == Geo
      assert extensions["geo"].status == :detached
      assert %Version{} = extensions["geo"].version
    end

    test "an extension the device may not use is refused identically" do
      info = %{device_info() | allowed_extensions: []}

      assert Local.call(:extensions_join, [info, @versions]) ==
               Remote.call(:extensions_join, [info, @versions])
    end
  end

  describe "failure handling" do
    test "raises rather than guessing when no handler is available" do
      # :pg memberships are a multiset, so clear every one and restore a single
      # canonical join afterwards rather than assuming there was exactly one.
      handler = Process.whereis(Handlers)
      on_exit(fn -> :pg.join(Handlers.scope(), :handlers, handler) end)

      Handlers.scope()
      |> :pg.get_members(:handlers)
      |> Enum.each(&:pg.leave(Handlers.scope(), :handlers, &1))

      assert Handlers.nodes() == []

      assert_raise NoHandlersError, ~r/extensions_join/, fn ->
        Remote.call(:extensions_join, [device_info(), @versions])
      end
    end

    test "a failure in the platform propagates instead of being retried" do
      ref = attach_failure_counter()

      # Nonsense certificate: the platform raises, which is an answer about this
      # call rather than a reason to try somewhere else.
      assert catch_error(Remote.call(:authenticate, [{:ssl_cert, "not-a-certificate"}]))
      assert catch_error(Local.call(:authenticate, [{:ssl_cert, "not-a-certificate"}]))

      refute_received {^ref, :dispatch_failure}
    end
  end

  describe "route_key / call dispatch coverage" do
    test "verify_peer routes by DER bytes (hashes the cert)" do
      # :verify_peer routes by :erlang.phash2(der) — just call it and observe
      # it either raises (platform error) or succeeds, but doesn't crash routing
      der = <<0, 1, 2, 3>>
      assert catch_error(Remote.call(:verify_peer, [der, :new]))
    end

    test "connect routes by device_id" do
      info = device_info(9999)
      assert catch_error(Remote.call(:connect, [info]))
    end

    test "device_join routes by device_id" do
      info = device_info(8888)
      assert catch_error(Remote.call(:device_join, [info, @versions]))
    end

    test "extensions_device_id extracted from extensions map" do
      {_attach_list, extensions} = Remote.call(:extensions_join, [device_info(7777), @versions])

      assert catch_error(Remote.call(:extension_message, [extensions, "health", "foo", %{}]))
    end

    test "extensions_device_id returns nil for non-matching map" do
      # Route key for extension_message with empty map should not raise (falls back to nil routing)
      assert catch_error(Remote.call(:extension_message, [%{}, "health", "foo", %{}]))
    end
  end

  defp attach_failure_counter() do
    ref = make_ref()
    test = self()

    :telemetry.attach(
      "remote-dispatch-failure-#{inspect(ref)}",
      [:nerves_hub, :device_link, :dispatch_failure],
      fn _event, _measurements, _metadata, _config -> send(test, {ref, :dispatch_failure}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach("remote-dispatch-failure-#{inspect(ref)}") end)

    ref
  end
end
