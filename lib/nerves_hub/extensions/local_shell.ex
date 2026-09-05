defmodule NervesHub.Extensions.LocalShell do
  @moduledoc """
  Gives a user a shell on the device.

  Unusually for an extension, nothing here touches the database — output is
  relayed to whoever is watching, and a bounded scrollback is kept so someone
  opening the tab can see what they missed.

  That scrollback stays on the connection rather than in this extension's state.
  A full one measures around 89KB, and extension state travels with every call,
  so a device writing steadily to its shell would otherwise send its entire
  backlog back and forth per line of output. See `NervesHub.DeviceLink.Effect`.
  """

  @behaviour NervesHub.Extensions

  alias NervesHub.Consoles
  alias NervesHub.ProductNotifications

  require Logger

  @impl NervesHub.Extensions
  def description() do
    """
    Connect to the devices local shell.
    """
  end

  @impl NervesHub.Extensions
  def enabled?() do
    true
  end

  @impl NervesHub.Extensions
  def attach(state) do
    key = Consoles.PubSub.local_shell_key(state.device_info.device_id)

    {state, [{:group_join, key}, {:push, "local_shell:request_shell", %{}}, {:scrollback_clear}]}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    key = Consoles.PubSub.local_shell_key(state.device_info.device_id)

    {state, [{:group_leave, key}, {:scrollback_clear}]}
  end

  @impl NervesHub.Extensions
  def handle_in("shell_output", %{"data" => data}, state) do
    :ok = Consoles.PubSub.broadcast_to_user_local_shell(state.device_info.device_id, "output", %{data: data})

    {state, [{:scrollback_append, data}]}
  end

  # The device answers `request_shell` with how it went. A failure here is not an
  # attach failure -- the extension is attached, and stays attached, so the shell
  # looks available right up until nothing happens when it is opened. That is the
  # case this notification exists for; `:expty` missing from a device's
  # dependencies is how it was found.
  def handle_in("request_status", %{"status" => "failed"} = payload, state) do
    _ =
      ProductNotifications.create_extension_failure_notification!(
        state.device_info,
        "local_shell",
        payload["reason"]
      )

    {state, []}
  end

  # A shell that started needs nothing from us, and is not an unknown message.
  def handle_in("request_status", _payload, state), do: {state, []}

  def handle_in(event, params, state) do
    Logger.warning(
      "[Extensions.LocalShell] unknown message received for device: #{inspect(state.device_info.device_id)} / #{inspect(event)} / #{inspect(params)}"
    )

    {state, []}
  end

  def handle_info({:connect, pid}, state) do
    {state, [{:scrollback_replay, pid}]}
  end

  @impl NervesHub.Extensions
  def handle_info(_msg, state) do
    {state, []}
  end
end
