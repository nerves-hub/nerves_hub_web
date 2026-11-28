defmodule NervesHub.RateLimit.Components do
  @moduledoc """
  How often one device may send components snapshots, readings and state
  changes.

  One bucket per kind, keyed by device, kept apart from other extensions for
  the reason `NervesHub.Extensions.Metrics` gives for its own. See
  `NervesHub.Extensions.Components` for the rates and what happens to a
  message this denies.
  """

  use Hammer, backend: :atomic, algorithm: :token_bucket
end
