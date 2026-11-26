defmodule NervesHubWeb.Live.AsyncTracingTest do
  @moduledoc """
  The trace a LiveComponent's and a device page tab's async work runs in.

  Both import `NervesHub.Telemetry.AsyncTrace`'s `start_async` and
  `assign_async` through `NervesHubWeb`, and their sockets are their
  LiveView's, so their spans are named after the LiveView.

  Not async: these swap the span exporter, which every test shares.
  """

  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Metrics

  require Record

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  # An exporter that declines to start, which puts the span processor back the
  # way it starts when no exporter is configured: off, and holding nothing.
  defmodule NoExporter do
    @moduledoc false
    def init(_config), do: :ignore
  end

  setup do
    :ok = :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
    on_exit(fn -> :ok = :otel_batch_processor.set_exporter(NoExporter, []) end)
  end

  test "a device page tab's loads are in the trace of the handle_params that opened it", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    device_info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }

    {:ok, 1} = Metrics.record(device_info, %{"cpu_temp" => 41.4})

    {:ok, lv, _html} = live(conn, "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/health")
    render_async(lv)

    spans = exported()

    # The Health tab's, started from its `tab_params` hook. The chart's async is
    # named `"load_chart:cpu_temp"`.
    assert [span(trace_id: trace_id, parent_span_id: parent_id)] =
             named(spans, "NervesHubWeb.Live.Devices.Show.start_async#load_chart")

    assert [span(trace_id: ^trace_id, parent_span_id: ^parent_id)] =
             named(spans, "NervesHubWeb.Live.Devices.Show.start_async#load_offline")

    assert [span(trace_id: ^trace_id, name: "NervesHubWeb.Live.Devices.Show.handle_params")] =
             for(span(span_id: ^parent_id) = span <- spans, do: span)
  end

  test "a LiveComponent's load is in the trace of the event that asked for it", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    {:ok, lv, _html} = live(conn, "/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
    render_async(lv)

    # Its update, on every page load, only sets assigns, so it gets no span.
    assert named(exported(), "NervesHubWeb.Live.Devices.Show.update#NervesHubWeb.Components.CommandPalette") == []

    # The command palette's search, an `assign_async` in its `handle_event`.
    lv
    |> element("#command-palette-form")
    |> render_change(%{"query" => device.identifier})

    assert render_async(lv) =~ device.identifier

    spans = exported()

    assert [span(trace_id: trace_id, parent_span_id: parent_id)] =
             named(spans, "NervesHubWeb.Live.Devices.Show.assign_async#results")

    assert [span(trace_id: ^trace_id, name: "NervesHubWeb.Live.Devices.Show.handle_event#search")] =
             for(span(span_id: ^parent_id) = span <- spans, do: span)
  end

  # Stats loads from its `update`, which LiveView calls while rendering, after
  # `handle_params` has returned (`NervesHub.Telemetry.ComponentTrace`).
  test "a LiveComponent's update, and the load it starts, are in the trace of the handle_params whose render ran it",
       %{conn: conn, org: org, product: product, deployment_group: deployment_group} do
    {:ok, lv, _html} =
      live(conn, "/org/#{org.name}/#{product.name}/deployment_groups/#{deployment_group.name}/stats")

    render_async(lv)

    spans = exported()

    assert [span(trace_id: trace_id, span_id: update_id, parent_span_id: parent_id)] =
             named(
               spans,
               "NervesHubWeb.Live.DeploymentGroups.Show.update#NervesHubWeb.Components.DeploymentGroupPage.Stats"
             )

    assert [span(trace_id: ^trace_id, name: "NervesHubWeb.Live.DeploymentGroups.Show.handle_params")] =
             for(span(span_id: ^parent_id) = span <- spans, do: span)

    assert [span(trace_id: ^trace_id, parent_span_id: ^update_id)] =
             named(spans, "NervesHubWeb.Live.DeploymentGroups.Show.start_async#history")

    # The queries `update` makes itself, such as the group's releases.
    assert [_ | _] = for(span(name: "nerves_hub.repo.query" <> _, parent_span_id: ^update_id) = span <- spans, do: span)
  end

  defp named(spans, name), do: for(span(name: ^name) = span <- spans, do: span)

  defp exported() do
    :otel_tracer_provider.force_flush()
    collect_exported([])
  end

  defp collect_exported(spans) do
    receive do
      {:span, span} -> collect_exported([span | spans])
    after
      200 -> spans
    end
  end
end
