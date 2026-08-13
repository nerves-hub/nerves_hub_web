defmodule NervesHubWeb.ExtensionsChannel do
  @moduledoc """
  Carries extension traffic between a device and the extension modules.

  Extensions do not touch the socket. They receive a `NervesHub.Extensions.State`
  and return `{state, effects}`; this channel holds that state, interprets the
  effects, and owns any timers they ask for. See `NervesHub.Extensions.State`.

  Timer and tick effects are delivered back as `{ExtensionModule, tag}`, which is
  also how outside callers reach an extension — `NervesHubWeb.UserLocalShellChannel`
  sends `{LocalShell, {:connect, pid}}`, for instance — so both arrive through the
  same dispatch path.
  """

  use Phoenix.Channel
  use OpenTelemetryDecorator

  alias NervesHub.Extensions
  alias NervesHub.Extensions.State
  alias NervesHub.Helpers.Logging
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  require Logger

  @impl Phoenix.Channel
  @decorate with_span("Channels.ExtensionsChannel.join")
  def join("extensions", extension_versions, %{assigns: %{device_info: device_info}} = socket) do
    extensions = load_and_parse_extensions(device_info, extension_versions)

    socket =
      socket
      |> assign(:extensions, extensions)
      |> assign(:extension_timers, %{})

    attach_list = for {key, %{attach?: true}} <- extensions, do: key

    if not Enum.empty?(attach_list) do
      send(self(), :init_extensions)
    end

    # all devices are lumped into a `extensions` topic (the name used in join/3)
    # this can be a security issue as pubsub messages can be sent to all connected devices
    # additionally, this topic isn't needed or used, so we can unsubscribe from it
    :ok = socket.endpoint.unsubscribe("extensions")

    topic = "device:#{device_info.device_id}:extensions"
    :ok = socket.endpoint.subscribe(topic)

    {:ok, attach_list, socket}
  end

  defp load_and_parse_extensions(device_info, extension_versions) do
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

  @impl Phoenix.Channel
  @decorate with_span("Channels.ExtensionsChannel.handle_in")
  def handle_in(scoped_event, payload, socket) do
    with [key, event] <- String.split(scoped_event, ":", parts: 2),
         %{attach?: true, status: status, module: mod} <- socket.assigns.extensions[key] do
      case event do
        "attached" ->
          socket
          |> put_status(key, :attached)
          |> dispatch(key, mod, &mod.attach/1)

        "detached" ->
          socket
          |> put_status(key, :detached)
          |> dispatch(key, mod, &mod.detach/1)

        "error" ->
          socket
          |> put_status(key, :detached)
          |> safe_dispatch(key, mod, &mod.handle_in(event, payload, &1), event)

        event when status == :attached ->
          safe_dispatch(socket, key, mod, &mod.handle_in(event, payload, &1), event)

        _ ->
          {:noreply, socket}
      end
    else
      _ ->
        # Unknown extension, tell device to detach it
        {:reply, {:error, "detach"}, socket}
    end
  end

  @impl Phoenix.Channel
  def handle_info(:init_extensions, socket) do
    topic = "product:#{socket.assigns.device_info.product_id}:extensions"
    :ok = PubSub.subscribe(NervesHub.PubSub, topic)

    {:noreply, socket}
  end

  @decorate with_span("Channels.ExtensionsChannel.handle_info[Broadcast]")
  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  @decorate with_span("Channels.ExtensionsChannel.handle_info[Broadcast]")
  def handle_info({mod, msg}, socket) do
    socket.assigns.extensions
    |> Enum.find(fn {_, v} -> v[:module] == mod && v[:status] == :attached end)
    |> case do
      nil ->
        {:noreply, socket}

      {key, _meta} ->
        safe_dispatch(socket, key, mod, &mod.handle_info(msg, &1), "handle_info")
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------- dispatch

  # Runs an extension callback, stores the state it returns, and carries out its
  # effects. Deliberately not rescued — matches the previous behaviour for
  # attach/detach, where a failure takes the channel down rather than leaving the
  # extension in an unknown state.
  defp dispatch(socket, key, mod, fun) do
    {state, effects} = fun.(extension_state(socket, key))

    socket
    |> put_state(key, state)
    |> apply_effects(key, mod, effects)
    |> then(&{:noreply, &1})
  end

  # As `dispatch/4`, but an extension raising is logged and swallowed so one
  # misbehaving extension cannot take the device's connection with it.
  defp safe_dispatch(socket, key, mod, fun, event) do
    dispatch(socket, key, mod, fun)
  rescue
    error ->
      Logger.warning("#{inspect(mod)} failed to handle extension message [#{event}] - #{inspect(error)}")

      Logging.log_to_sentry(socket.assigns.device_info, error)
      {:noreply, socket}
  end

  defp extension_state(socket, key), do: socket.assigns.extensions[key].state

  defp put_state(socket, key, state) do
    update_in(socket.assigns.extensions[key], &%{&1 | state: state})
  end

  defp put_status(socket, key, status) do
    update_in(socket.assigns.extensions[key], &%{&1 | status: status})
  end

  # ---------------------------------------------------------------- effects

  defp apply_effects(socket, key, mod, effects) do
    Enum.reduce(effects, socket, &apply_effect(&2, key, mod, &1))
  end

  defp apply_effect(socket, _key, _mod, {:push, event, payload}) do
    push(socket, event, payload)
    socket
  end

  defp apply_effect(socket, _key, mod, {:tick, tag}) do
    send(self(), {mod, tag})
    socket
  end

  defp apply_effect(socket, key, mod, {:start_timer, tag, interval_ms}) do
    socket = cancel_timer(socket, key, tag)
    {:ok, ref} = :timer.send_interval(interval_ms, {mod, tag})

    update_in(socket.assigns.extension_timers, &Map.put(&1, {key, tag}, ref))
  end

  defp apply_effect(socket, key, _mod, {:cancel_timer, tag}) do
    cancel_timer(socket, key, tag)
  end

  defp cancel_timer(socket, key, tag) do
    case Map.pop(socket.assigns.extension_timers, {key, tag}) do
      {nil, _timers} ->
        socket

      {ref, timers} ->
        _ = :timer.cancel(ref)
        assign(socket, :extension_timers, timers)
    end
  end
end
