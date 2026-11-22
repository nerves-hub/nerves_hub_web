defmodule NervesHub.DeviceLink.Dispatcher.RemoteTest do
  @moduledoc """
  The dispatcher that runs DeviceLink calls somewhere else.

  The equivalence tests here matter more than the mechanics ones. A caller that
  is not carrying the platform stack has to get the same answers as one that is,
  or devices behave differently depending on what they happened to connect to —
  and that difference would only show up in production.
  """

  # Not async: a call runs in a process erpc starts, which only reaches the
  # database through the shared sandbox.
  use NervesHub.DataCase, async: false

  alias NervesHub.DeviceLink
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.DeviceLink.Dispatcher.Local
  alias NervesHub.DeviceLink.Dispatcher.NoHandlersError
  alias NervesHub.DeviceLink.Dispatcher.Remote
  alias NervesHub.DeviceLink.Handlers
  alias NervesHub.DeviceLink.Session
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Extensions.Geo
  alias NervesHub.Fixtures

  require OpenTelemetry.Tracer, as: Tracer
  require Record

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  # An exporter that declines to start, which puts the span processor back the
  # way it starts when no exporter is configured: off, and holding nothing.
  defmodule NoExporter do
    @moduledoc false
    def init(_config), do: :ignore
  end

  @versions %{"health" => "0.0.1", "geo" => "0.0.1", "local_shell" => "0.0.1"}

  defp device_info(device_id \\ 4242)

  defp device_info(%Device{} = device) do
    %DeviceInfo{
      allowed_extensions: [:health, :geo, :local_shell],
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }
  end

  defp device_info(device_id) do
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

  # Spans come to this process through the SDK's own span processor, which every
  # tracer already reports to. Other tests' spans arrive too, so each test looks
  # only at its own trace.
  describe "the trace a call is made in" do
    setup do
      :ok = :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
      on_exit(fn -> :ok = :otel_batch_processor.set_exporter(NoExporter, []) end)
    end

    test "carries on in a span the platform opens for the call" do
      caller =
        Tracer.with_span "Channels.DeviceChannel.handle_in" do
          assert is_boolean(Remote.call(:shared_secrets_enabled?, []))
          Tracer.current_span_ctx()
        end

      caller_span_id = OpenTelemetry.Span.span_id(caller)

      assert [span(name: "DeviceLink.shared_secrets_enabled?", parent_span_id: ^caller_span_id, kind: :server)] =
               caller |> OpenTelemetry.Span.trace_id() |> exported() |> Enum.reject(&(span(&1, :name) =~ "Channels."))
    end

    test "a trace the caller kept is kept, with Sentry's decision in the trace state" do
      trace_id = continue_trace(sampled?: true)

      assert is_boolean(Remote.call(:shared_secrets_enabled?, []))

      assert [span(name: "DeviceLink.shared_secrets_enabled?", tracestate: tracestate)] = exported(trace_id)
      assert :otel_tracestate.get("sentry-sampled", tracestate) == "true"
    end

    test "says which device a call is about, and what about it" do
      trace_id = continue_trace(sampled?: true)

      {_attach_list, extensions} = Remote.call(:extensions_join, [device_info(), @versions])
      assert Remote.call(:extension_message, [extensions, "nope:hello", %{}]) == :unknown

      spans = for span(name: name, attributes: attributes) <- exported(trace_id), into: %{}, do: {name, attributes}
      device = %{"nerves_hub.device.id": 4242, "nerves_hub.product.id": 2, "nerves_hub.org.id": 1}

      assert :otel_attributes.map(spans["DeviceLink.extensions_join"]) == device

      assert :otel_attributes.map(spans["DeviceLink.extension_message"]) ==
               Map.put(device, :"nerves_hub.channel.event", "nope:hello")
    end

    test "a trace the caller dropped is dropped" do
      trace_id = continue_trace(sampled?: false)

      assert is_boolean(Remote.call(:shared_secrets_enabled?, []))

      assert exported(trace_id) == []
    end
  end

  # How other applications' nodes call this one. They can't be checked from here,
  # so this pins what they rely on.
  describe "run/3, as another node calls it" do
    test "answers as the DeviceLink function does" do
      assert :erpc.call(node(), Remote, :run, [[], :shared_secrets_enabled?, []]) ==
               DeviceLink.shared_secrets_enabled?()
    end

    test "raises what the DeviceLink function raises, unchanged" do
      # No clause takes a status update without a status. Rescued and raised again
      # on the way, it would come back as a FunctionClauseError instead.
      assert catch_error(Local.call(:status_update, [nil, %{}])) == :function_clause

      assert {:exception, :function_clause, _stack} =
               catch_error(:erpc.call(node(), Remote, :run, [[], :status_update, [nil, %{}]]))
    end
  end

  # One node handles every call here, so which node a call lands on can't be
  # seen. What can is that each kind of argument the router reads a device from
  # gets through it, and the call is then carried out for that device, as
  # DeviceLink itself would carry it out.
  describe "routing each kind of call" do
    test "a handshake routes by its certificate" do
      # Not a certificate, which the handler finds out when it decodes it.
      assert {:exception, {:badmatch, {:error, {:asn1, _reason}}}, _stack} =
               catch_error(Remote.call(:verify_peer, [<<0, 1, 2, 3>>, :new]))
    end

    test "connect routes by the device it is given", %{tmp_dir: tmp_dir} do
      device = device_fixture(tmp_dir)

      assert {:ok, %DeviceInfo{connection_ref: ref}} = Remote.call(:connect, [device_info(device)])
      assert %DeviceConnection{id: ^ref} = Connections.get_latest_for_device(device.id)
    end

    test "device_join routes by the device it is given", %{tmp_dir: tmp_dir} do
      device = device_fixture(tmp_dir)
      {:ok, %DeviceInfo{connection_ref: ref} = device_info} = Remote.call(:connect, [device_info(device)])
      device_id = device.id

      assert {:ok, %Session{device_info: %DeviceInfo{device_id: ^device_id, connection_ref: ^ref}}, _effects} =
               Remote.call(:device_join, [device_info, %{"device_api_version" => "2.2.0"}])
    end

    test "an extension message routes by the device its extensions belong to" do
      {_attach_list, extensions} = Remote.call(:extensions_join, [device_info(7777), @versions])

      assert Remote.call(:extension_message, [extensions, "health:hello", %{}]) ==
               Local.call(:extension_message, [extensions, "health:hello", %{}])
    end

    test "an extension message with no device in its extensions is still carried out" do
      assert Remote.call(:extension_message, [%{}, "health:hello", %{}]) == :unknown
    end
  end

  defp device_fixture(tmp_dir) do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    Fixtures.device_fixture(org, product, firmware)
  end

  # Joins a trace as a caller holds it once its own sampler has decided. Sentry's
  # sampler writes its decision into the trace state, and a span continuing the
  # trace inherits it from there.
  defp continue_trace(sampled?: sampled?) do
    trace_id = :rand.uniform(2 ** 128 - 1)
    span_id = :rand.uniform(2 ** 64 - 1)
    flags = if sampled?, do: "01", else: "00"

    _token =
      :otel_propagator_text_map.extract([
        {"traceparent", "00-#{hex(trace_id, 32)}-#{hex(span_id, 16)}-#{flags}"},
        {"tracestate", "sentry-sampled=#{sampled?}"}
      ])

    trace_id
  end

  defp hex(id, length), do: id |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(length, "0")

  defp exported(trace_id) do
    :otel_tracer_provider.force_flush()
    collect_exported(trace_id, [])
  end

  defp collect_exported(trace_id, spans) do
    receive do
      {:span, span(trace_id: ^trace_id) = span} -> collect_exported(trace_id, [span | spans])
      {:span, _other} -> collect_exported(trace_id, spans)
    after
      200 -> Enum.reverse(spans)
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
