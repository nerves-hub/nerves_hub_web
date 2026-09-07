defmodule TrackerHelper do
  @moduledoc false

  alias NervesHub.Devices.PubSub

  @doc """
  Join the calling process to a device's event group.

  Kept as a plain function (rather than inline in the macros below) so the
  `NervesHub.Devices.PubSub` reference can be aliased — a `quote` block expands
  in the caller's context, where the alias would not exist.
  """
  def subscribe_to_device(device) do
    PubSub.subscribe(device.id)
  end

  defmacro subscribe_for_updates(device) do
    quote do
      TrackerHelper.subscribe_to_device(unquote(device))
    end
  end

  defmacro assert_connection_change() do
    quote do
      assert_receive %{event: "connection:change"}
    end
  end

  defmacro refute_online(device) do
    quote do
      TrackerHelper.subscribe_to_device(unquote(device))
      NervesHub.Tracker.online?(unquote(device))
      refute_receive %{event: "connection:change"}
    end
  end
end
