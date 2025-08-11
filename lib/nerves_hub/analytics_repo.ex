defmodule NervesHub.AnalyticsRepo do
  use Ecto.Repo,
    otp_app: :nerves_hub,
    adapter: Ecto.Adapters.ClickHouse
end
