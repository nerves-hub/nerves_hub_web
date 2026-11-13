defmodule NervesHub.RateLimit.Alarms do
  @moduledoc """
  How often one device may send alarm events.

  Its own bucket, for the reason `NervesHub.Extensions.Metrics` gives for its
  own: a device in trouble raises alarms, reports errors and logs all at once,
  and none of them should starve the others. See `NervesHub.Extensions.Alarms`
  for what happens to a message this denies.
  """

  use Hammer, backend: :atomic, algorithm: :token_bucket
end
