defmodule NervesHub.DeviceLink.Effect do
  @moduledoc """
  The vocabulary `NervesHub.DeviceLink` uses to ask for something that only the
  process holding a device's connection can do.

  Everything the platform can do by itself — a database write, a PubSub
  broadcast, a `send/2` to a pid it already knows — it does directly. Effects
  cover only the rest:

    * `{:push, event, payload}` — send a message to the device
    * `{:subscribe, topic}` / `{:unsubscribe, topic}` — follow or stop following
      a PubSub topic on the connection's behalf
    * `{:send_self, message}` — deliver `message` back to the connection now
    * `{:send_after, key, message, delay_ms}` — deliver it once, later
    * `{:start_timer, key, message, interval_ms}` — deliver it repeatedly
    * `{:cancel_timer, key}` — stop a timer started under `key`
    * `{:scrollback_append, data}` — record terminal output for later replay
    * `{:scrollback_replay, pid}` — send everything recorded to `pid` as `{:cache, text}`
    * `{:scrollback_clear}` — forget it

  `message` and `key` are opaque to whoever carries the effect out: it sends the
  one and files timers under the other, and inspects neither. That is what lets
  a connection be held somewhere that has none of the platform's code.

  Scrollback is here for the same reason timers are. The platform has no use for
  a device's terminal output beyond passing it on, and the record is large and
  changes on every line — so it stays on the connection, and the platform only
  says when to add to it and who to replay it to.
  """

  @type t() ::
          {:push, event :: String.t(), payload :: map()}
          | {:subscribe, topic :: String.t()}
          | {:unsubscribe, topic :: String.t()}
          | {:send_self, message :: term()}
          | {:send_after, key :: term(), message :: term(), delay_ms :: non_neg_integer()}
          | {:start_timer, key :: term(), message :: term(), interval_ms :: pos_integer()}
          | {:cancel_timer, key :: term()}
          | {:scrollback_append, data :: binary()}
          | {:scrollback_replay, pid()}
          | {:scrollback_clear}
end
