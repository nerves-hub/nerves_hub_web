defmodule NervesHub.PromEx do
  use PromEx, otp_app: :nerves_hub

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # PromEx built in plugins
      Plugins.Application,
      Plugins.Beam,
      {
        PromEx.Plugins.Phoenix,
        endpoints: [
          {NervesHubWeb.Endpoint, routers: [NervesHubWeb.Router]},
          # DeviceEndpoint doesn't use a Router, but we need to pass to PromEx
          {NervesHubWeb.DeviceEndpoint, routers: [NervesHubWeb.Router]}
        ]
      },
      Plugins.PhoenixLiveView,
      Plugins.Ecto,
      Plugins.Oban
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus"
    ]
  end

  @impl true
  def dashboards do
    [
      # PromEx built in Grafana dashboards
      {:prom_ex, "beam.json"},
      {:nerves_hub, "grafana/phoenix.json"},
      {:nerves_hub, "grafana/phoenix_live_view.json"},
      {:nerves_hub, "grafana/ecto.json"},
      {:nerves_hub, "grafana/oban.json"}
    ]
  end
end
