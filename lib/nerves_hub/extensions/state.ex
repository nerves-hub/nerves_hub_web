defmodule NervesHub.Extensions.State do
  @moduledoc """
  Per-extension state, and the effects an extension can ask for.

  Extensions used to receive and return a `Phoenix.Socket`, which coupled them to
  the process holding the device connection. That works while the socket and the
  business logic live on the same node, but not once the socket moves to a
  separate application that has no database and no platform logic.

  So an extension now receives this struct and returns `{state, effects}`. The
  caller — today `NervesHubWeb.ExtensionsChannel` — decides how to carry the
  effects out. Anything an extension can do on its own (a database write, a
  PubSub broadcast, a `send/2` to a known pid) it still does directly; only the
  things that need the connection are expressed as effects.

  Each extension gets its own `assigns` map rather than sharing one, so two
  extensions cannot collide on a key.
  """

  alias NervesHub.DeviceLink.DeviceInfo

  defstruct [:device_info, assigns: %{}]

  @typedoc """
  Something only the process holding the device connection can do.

  - `{:push, event, payload}` — send a message to the device
  - `{:tick, tag}` — deliver `tag` back to this extension's `handle_info/2` now
  - `{:start_timer, tag, interval_ms}` — deliver `tag` back every `interval_ms`
  - `{:cancel_timer, tag}` — stop a timer started with `:start_timer`

  `:tick` and `:start_timer` exist because an extension can no longer reach for
  `send(self(), ...)` or `:timer.send_interval/2` — it does not own the process
  that would receive them.

  The scrollback effects are for output an extension wants remembered but has no
  use for itself; see `NervesHub.DeviceLink.Effect`. They pass through to the
  caller unchanged, since they name nothing extension-specific.

  - `{:group_join, key}` / `{:group_leave, key}` — join or leave a `:group` key

  These pass through unchanged for the same reason. An extension cannot join a
  group itself: `Group.join/4` joins the calling process, and the process that
  needs to be a member is the one holding the connection, which the extension
  does not own — the same reason `:tick` and `:start_timer` exist.
  """
  @type effect ::
          {:push, event :: String.t(), payload :: map()}
          | {:tick, tag :: term()}
          | {:start_timer, tag :: term(), interval_ms :: pos_integer()}
          | {:cancel_timer, tag :: term()}
          | {:scrollback_append, data :: binary()}
          | {:scrollback_replay, pid()}
          | {:scrollback_clear}
          | {:group_join, key :: String.t()}
          | {:group_leave, key :: String.t()}

  @type t :: %__MODULE__{
          device_info: DeviceInfo.t(),
          assigns: map()
        }

  @doc "Build empty state for a device."
  @spec new(DeviceInfo.t()) :: t()
  def new(%DeviceInfo{} = device_info), do: %__MODULE__{device_info: device_info}

  @doc "Store a value in this extension's assigns."
  @spec assign(t(), atom(), term()) :: t()
  def assign(%__MODULE__{} = state, key, value) when is_atom(key) do
    %{state | assigns: Map.put(state.assigns, key, value)}
  end

  @doc "Read a value from this extension's assigns."
  @spec get(t(), atom(), term()) :: term()
  def get(%__MODULE__{} = state, key, default \\ nil) when is_atom(key) do
    Map.get(state.assigns, key, default)
  end
end
