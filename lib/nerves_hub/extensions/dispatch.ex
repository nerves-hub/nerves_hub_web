defmodule NervesHub.Extensions.Dispatch do
  @moduledoc """
  Routes device extension traffic to extension modules.

  Reached through `NervesHub.DeviceLink`, which is the contract the process
  holding a device connection is allowed to depend on. Everything about
  extensions that is business logic — which module serves a key, whether it is
  enabled, whether it is currently attached, and what happens when it raises —
  lives here.

  Callers get back effects with routing already resolved, so they never need to
  know an extension module name. `NervesHub.Extensions.State` describes the
  effects an extension itself emits; this module translates those into the
  caller-facing ones below.
  """

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.DeviceLink.Effect
  alias NervesHub.Extensions
  alias NervesHub.Extensions.State
  alias NervesHub.Helpers.Logging

  require Logger

  @typedoc "Per-key extension bookkeeping, opaque to callers."
  @type extensions() :: %{String.t() => map()}

  @typedoc """
  An effect for the caller to carry out on the device connection.

  Routing is already resolved — see `NervesHub.DeviceLink.Effect`.
  """
  @type effect() :: Effect.t()

  @doc """
  Work out which extensions this device may use, given the versions it reports.

  Returns the keys the device should attach, and the bookkeeping to hand back on
  subsequent calls.
  """
  @spec join(DeviceInfo.t(), extension_versions :: map()) :: {[String.t()], extensions()}
  def join(device_info, extension_versions) do
    extensions = load_and_parse(device_info, extension_versions)
    attach_list = for {key, %{attach?: true}} <- extensions, do: key

    {attach_list, extensions}
  end

  @doc """
  Handle a `"<key>:<event>"` message from the device.

  Returns `:unknown` when the device is talking about an extension it may not
  use, which the caller should answer by telling it to detach.
  """
  @spec message(extensions(), scoped_event :: String.t(), payload :: term()) ::
          {:ok, extensions(), [effect()]} | :unknown
  def message(extensions, scoped_event, payload) do
    with [key, event] <- String.split(scoped_event, ":", parts: 2),
         %{attach?: true, status: status, module: mod} <- extensions[key] do
      case event do
        "attached" ->
          extensions
          |> put_status(key, :attached)
          |> dispatch(key, mod, &mod.attach/1)

        "detached" ->
          extensions
          |> put_status(key, :detached)
          |> dispatch(key, mod, &mod.detach/1)

        "error" ->
          extensions
          |> put_status(key, :detached)
          |> safe_dispatch(key, mod, &mod.handle_in(event, payload, &1), event)

        event when status == :attached ->
          safe_dispatch(extensions, key, mod, &mod.handle_in(event, payload, &1), event)

        _ ->
          {:ok, extensions, []}
      end
    else
      _ -> :unknown
    end
  end

  @doc """
  Deliver a message addressed to an extension module.

  Covers both timers this module asked the caller to set and messages from
  elsewhere in the system — `NervesHubWeb.UserLocalShellChannel` sends
  `{LocalShell, {:connect, pid}}`, for example. Messages for an extension that
  is not attached are dropped.
  """
  @spec info(extensions(), module(), msg :: term()) :: {:ok, extensions(), [effect()]}
  def info(extensions, mod, msg) do
    extensions
    |> Enum.find(fn {_key, meta} -> meta[:module] == mod && meta[:status] == :attached end)
    |> case do
      nil ->
        {:ok, extensions, []}

      {key, _meta} ->
        safe_dispatch(extensions, key, mod, &mod.handle_info(msg, &1), "handle_info")
    end
  end

  # ---------------------------------------------------------------- internals

  defp load_and_parse(device_info, extension_versions) do
    for {key_str, version} <- extension_versions, into: %{} do
      meta =
        case Version.parse(version) do
          {:ok, ver} ->
            extension = Enum.find(device_info.allowed_extensions, &(to_string(&1) == key_str))

            if extension do
              mod = Extensions.module(extension, ver)
              attach = Code.ensure_loaded?(mod) && mod.enabled?()

              %{
                attach?: attach,
                version: ver,
                module: mod,
                status: :detached,
                state: State.new(device_info)
              }
            else
              unsupported(version)
            end

          _ ->
            unsupported(version)
        end

      {key_str, meta}
    end
  end

  defp unsupported(version) do
    %{attach?: false, version: version, module: nil, status: :detached, state: nil}
  end

  # Deliberately not rescued, matching the previous behaviour for attach/detach:
  # a failure there takes the connection down rather than leaving the extension
  # in a state nobody can reason about.
  defp dispatch(extensions, key, mod, fun) do
    {state, effects} = fun.(extensions[key].state)

    {:ok, put_state(extensions, key, state), Enum.map(effects, &translate(&1, key, mod))}
  end

  # As `dispatch/4`, but an extension raising is logged and swallowed so one
  # misbehaving extension cannot take the device's connection with it.
  defp safe_dispatch(extensions, key, mod, fun, event) do
    dispatch(extensions, key, mod, fun)
  rescue
    error ->
      Logger.warning("#{inspect(mod)} failed to handle extension message [#{event}] - #{inspect(error)}")

      Logging.log_to_sentry(device_info(extensions, key), error)
      {:ok, extensions, []}
  end

  # Extensions speak in their own tags; callers need something they can send and
  # something they can key a timer by, without knowing which module is involved.
  defp translate({:tick, tag}, _key, mod), do: {:send_self, {mod, tag}}
  defp translate({:start_timer, tag, ms}, key, mod), do: {:start_timer, {key, tag}, {mod, tag}, ms}
  defp translate({:cancel_timer, tag}, key, _mod), do: {:cancel_timer, {key, tag}}

  # Effects that name no extension-specific thing pass straight through.
  defp translate({:push, _event, _payload} = effect, _key, _mod), do: effect
  defp translate({:scrollback_append, _data} = effect, _key, _mod), do: effect
  defp translate({:scrollback_replay, _pid} = effect, _key, _mod), do: effect
  defp translate({:scrollback_clear} = effect, _key, _mod), do: effect

  defp put_state(extensions, key, state) do
    update_in(extensions[key], &%{&1 | state: state})
  end

  defp put_status(extensions, key, status) do
    update_in(extensions[key], &%{&1 | status: status})
  end

  defp device_info(extensions, key), do: extensions[key].state.device_info
end
