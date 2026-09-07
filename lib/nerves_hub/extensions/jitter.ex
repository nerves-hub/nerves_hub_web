defmodule NervesHub.Extensions.Jitter do
  @moduledoc """
  Picks a random start offset so a fleet does not ask in unison.

  An extension that starts a repeating timer on attach gives every device the
  same phase, because they attach together: a deploy reconnects the whole fleet
  inside a few seconds, and that alignment lasts as long as the connections do.
  Measured on a production device node, 74% of 1519 devices had their health
  check due inside the same 30 second window, against the 5% an even spread
  would put there. An hour later it had barely moved, because device
  connections are long-lived -- only the handful that had reconnected since
  were spread out.

  What that costs is one burst per interval instead of a steady trickle: every
  device pushed a request at once, every device answering at once, and two
  database writes per answer. It shows up as a spike in CPU, in egress and in
  database traffic, at exactly the interval length.

  Only the first delay is offset. The period after that is exact, so a device
  asked to report every ten minutes still reports every ten minutes -- it just
  starts somewhere random inside the first one. That also decouples the phase
  from the connect time, so devices reconnecting together stops mattering
  rather than having to even out on its own.

  `NervesHubWeb.DeviceSocket` staggers last-seen updates for the same reason,
  which is why those never showed up as a spike.
  """

  @doc """
  A random delay in `1..interval_ms`, for the first fire of a repeating timer.

  Uniform across the whole interval, so a fleet attaching at the same instant
  ends up evenly spread rather than merely smeared.
  """
  @spec start_delay(pos_integer()) :: pos_integer()
  def start_delay(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    Enum.random(1..interval_ms)
  end
end
