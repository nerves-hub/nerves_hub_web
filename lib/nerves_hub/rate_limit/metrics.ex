defmodule NervesHub.RateLimit.Metrics do
  @moduledoc """
  Per-device budgets for the metrics write path. Two callers keep buckets here,
  under keys of their own, at rates of their own:

    * `NervesHub.Extensions.Metrics` limits how often a device may send a
      report message (`"metrics_device_<id>"`). The platform sets the pace it
      asks for reports at, but a device can also report unasked.
    * `NervesHub.Devices.Metrics` limits how often a device's bad reports are
      raised to its operators (`"device_<id>"`). A client generating names that
      are too long, or too many of them, does it on every report forever, and
      each `ProductNotifications` write costs a PostgreSQL upsert and a
      broadcast on the metrics write path.

  Each caller's rate, and why, is with the caller.
  """

  use Hammer, backend: :atomic, algorithm: :token_bucket
end
