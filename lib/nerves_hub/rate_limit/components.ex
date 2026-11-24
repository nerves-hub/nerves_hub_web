defmodule NervesHub.RateLimit.Components do
  @moduledoc """
  How often one device may send a components snapshot.

  Its own bucket, for the reason `NervesHub.Extensions.Metrics` gives for its
  own. See `NervesHub.Extensions.Components` for what happens to a snapshot
  this denies.
  """

  use Hammer, backend: :atomic, algorithm: :token_bucket
end
