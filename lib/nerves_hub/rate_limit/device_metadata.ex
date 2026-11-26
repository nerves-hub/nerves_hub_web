defmodule NervesHub.RateLimit.DeviceMetadata do
  @moduledoc """
  How often one device's dropped metadata is raised to its operators.

  A device whose firmware reports metadata over the limits does it on every
  join and every health report, forever. See
  `NervesHub.Devices.ReportedMetadata` for the rate.
  """

  use Hammer, backend: :atomic, algorithm: :token_bucket
end
