defmodule NervesHub.StatsdMetricsReporter do
  import Telemetry.Metrics

  def config() do
    statsd_config = Application.get_env(:nerves_hub, :statsd, [])

    if statsd_config[:host] do
      [
        {TelemetryMetricsStatsd,
         host: statsd_config[:host],
         port: statsd_config[:port],
         formatter: :datadog,
         metrics: [
           # NervesHub
           counter("nerves_hub.devices.connect.count", tags: [:env, :service]),
           counter("nerves_hub.devices.disconnect.count", tags: [:env, :service]),
           counter("nerves_hub.devices.duplicate_connection", tags: [:env, :service]),
           counter("nerves_hub.devices.deployment.changed.count", tags: [:env, :service]),
           counter("nerves_hub.devices.deployment.update.manual.count", tags: [:env, :service]),
           counter("nerves_hub.devices.deployment.update.automatic.count", tags: [:env, :service]),
           counter("nerves_hub.devices.deployment.penalty_box.check.count",
             tags: [:env, :service]
           ),
           counter("nerves_hub.deployments.trigger_update.count", tags: [:env, :service]),
           counter("nerves_hub.deployments.trigger_update.device.count", tags: [:env, :service]),
           counter("nerves_hub.devices.jitp.created.count", tags: [:env, :service]),
           counter("nerves_hub.device_certificates.created.count", tags: [:env, :service]),
           last_value("nerves_hub.devices.online.count", tags: [:env, :service, :node]),
           counter("nerves_hub.rate_limit.accepted.count", tags: [:env, :service]),
           counter("nerves_hub.rate_limit.pruned.count", tags: [:env, :service]),
           counter("nerves_hub.rate_limit.rejected.count", tags: [:env, :service]),
           counter("nerves_hub.ssl.fail.count", tags: [:env, :service]),
           counter("nerves_hub.ssl.success.count", tags: [:env, :service]),
           counter("nerves_hub.tracker.exception.count", tags: [:env, :service]),
           # General
           counter("phoenix.endpoint.start.count", tags: [:env, :service]),
           summary("phoenix.endpoint.stop.duration",
             tags: [:env, :service],
             unit: {:native, :millisecond}
           ),
           summary("phoenix.router_dispatch.stop.duration",
             tags: [:route, :env, :service],
             unit: {:native, :millisecond}
           ),
           counter("nerves_hub.repo.query.count", tags: [:env, :service]),
           distribution("nerves_hub.repo.query.idle_time",
             tags: [:env, :service],
             unit: {:native, :millisecond}
           ),
           distribution("nerves_hub.repo.query.queue_time",
             tags: [:env, :service],
             unit: {:native, :millisecond}
           ),
           distribution("nerves_hub.repo.query.query_time",
             tags: [:env, :service],
             unit: {:native, :millisecond}
           ),
           distribution("nerves_hub.repo.query.decode_time",
             tags: [:env, :service],
             unit: {:native, :millisecond}
           ),
           distribution("nerves_hub.repo.query.total_time",
             tags: [:env, :service],
             unit: {:native, :millisecond}
           ),
           summary("vm.memory.total", tags: [:env, :service], unit: {:byte, :kilobyte}),
           summary("vm.total_run_queue_lengths.total", tags: [:env, :service]),
           summary("vm.total_run_queue_lengths.cpu", tags: [:env, :service]),
           summary("vm.total_run_queue_lengths.io", tags: [:env, :service])
         ],
         global_tags: [
           env: Application.get_env(:nerves_hub, :deploy_env),
           dyno: Application.get_env(:nerves_hub, :app),
           service: "nerves_hub"
         ]}
      ]
    else
      []
    end
  end
end
