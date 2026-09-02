defmodule NervesHub.RateLimit.Metrics do
  @moduledoc """
  How often one device may have a bad metric report raised to its operators.

  Not a limit on reporting -- the pace of metric reports is set by the platform,
  so a device cannot flood it. This throttles the `ProductNotifications` write
  that `NervesHub.Devices.Metrics` makes when a report carries keys it will not
  store: a client generating names that are too long, or too many of them, does
  it on every report forever, and each one would otherwise cost a PostgreSQL
  upsert and a broadcast on the metrics write path.
  """

  use Hammer, backend: :atomic, algorithm: :token_bucket
end
