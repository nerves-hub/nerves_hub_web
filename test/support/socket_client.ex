defmodule SocketClient do
  use Slipstream, restart: :temporary

  def start_link(args) do
    Slipstream.start_link(__MODULE__, args)
  end

  def connected?(socket) do
    GenServer.call(socket, :connected?)
  end

  def connecting?(socket) do
    GenServer.call(socket, :connecting?)
  end

  def joined?(socket) do
    GenServer.call(socket, :joined?)
  end

  def close(socket) do
    GenServer.stop(socket)
  end

  def reply(socket) do
    GenServer.call(socket, :reply)
  end

  def join(socket, channel, params \\ %{}) do
    GenServer.call(socket, {:join, channel, params})
  end

  def status(socket) do
    GenServer.call(socket, :status)
  end

  def state(socket) do
    GenServer.call(socket, :state)
  end

  def wait_connect(_, _ \\ nil)

  def wait_connect(socket, nil) do
    timeout = 2_000
    {:ok, t_ref} = :timer.exit_after(timeout, "Timed out waiting for socket connect")
    wait_connect(socket, t_ref)
  end

  def wait_connect(socket, timer) do
    if __MODULE__.connecting?(socket) do
      wait_connect(socket, timer)
    else
      :timer.cancel(timer)
    end
  end

  def wait_join(_, _ \\ nil)

  def wait_join(socket, nil) do
    timeout = 2_000
    {:ok, t_ref} = :timer.exit_after(timeout, "Timed out waiting for socket join")
    wait_join(socket, t_ref)
  end

  def wait_join(socket, timer) do
    if __MODULE__.joined?(socket) do
      :timer.cancel(timer)
    else
      wait_join(socket, timer)
    end
  end

  def received_archive?(socket) do
    GenServer.call(socket, :received_archive?)
  end

  def wait_archive(_, _ \\ nil)

  def wait_archive(socket, nil) do
    timeout = 2_000
    {:ok, t_ref} = :timer.exit_after(timeout, "Timed out waiting for a firmware archive")
    wait_archive(socket, t_ref)
  end

  def wait_archive(socket, timer) do
    if __MODULE__.received_archive?(socket) do
      {:ok, :cancel} = :timer.cancel(timer)
      GenServer.call(socket, :archive_message)
    else
      wait_archive(socket, timer)
    end
  end

  def received_update?(socket) do
    GenServer.call(socket, :received_update?)
  end

  def wait_update(_, _ \\ nil)

  def wait_update(socket, nil) do
    timeout = 2_000
    {:ok, t_ref} = :timer.exit_after(timeout, "Timed out waiting for a firmware update")
    wait_update(socket, t_ref)
  end

  def wait_update(socket, timer) do
    if __MODULE__.received_update?(socket) do
      {:ok, :cancel} = :timer.cancel(timer)
      GenServer.call(socket, :update_message)
    else
      wait_update(socket, timer)
    end
  end

  @impl true
  def init(config) do
    Process.flag(:trap_exit, true)

    socket =
      new_socket()
      |> assign(:connected?, false)
      |> assign(:connecting?, true)
      |> assign(:joined?, false)
      |> assign(:reply, nil)
      |> assign(:received_update?, false)
      |> assign(:update, nil)
      |> assign(:received_archive?, false)
      |> assign(:received_check_health?, false)
      |> assign(:archive, nil)
      |> assign(:error_code, nil)
      |> assign(:error_reason, nil)
      |> connect!(config)

    {:ok, socket}
  end

  @impl true
  def handle_connect(socket) do
    socket =
      socket
      |> assign(:connected?, true)
      |> assign(:connecting?, false)

    {:ok, socket}
  end

  @impl true
  def handle_join(_channel, reply, socket) do
    socket =
      socket
      |> assign(:joined?, true)
      |> assign(:reply, reply)

    {:ok, socket}
  end

  @impl true
  def handle_message("device", "update", message, socket) do
    socket =
      socket
      |> assign(:received_update?, true)
      |> assign(:update, message)

    {:ok, socket}
  end

  def handle_message("device", "archive", message, socket) do
    socket =
      socket
      |> assign(:received_archive?, true)
      |> assign(:archive, message)

    {:ok, socket}
  end

  def handle_message("device", "check_health", %{}, socket) do
    socket =
      socket
      |> assign(:receive_check_helth?, true)

    {:ok, socket}
  end

  @impl true
  def handle_call(:connected?, _from, socket) do
    {:reply, socket.assigns.connected?, socket}
  end

  def handle_call(:connecting?, _from, socket) do
    {:reply, socket.assigns.connecting?, socket}
  end

  def handle_call(:joined?, _from, socket) do
    {:reply, socket.assigns.joined?, socket}
  end

  def handle_call(:received_archive?, _from, socket) do
    {:reply, socket.assigns.received_archive?, socket}
  end

  def handle_call(:archive_message, _from, socket) do
    socket = assign(socket, :received_archive?, false)
    {:reply, socket.assigns.archive, socket}
  end

  def handle_call(:received_update?, _from, socket) do
    {:reply, socket.assigns.received_update?, socket}
  end

  def handle_call(:update_message, _from, socket) do
    {:reply, socket.assigns.update, socket}
  end

  def handle_call(:reply, _from, socket) do
    {:reply, socket.assigns.reply, socket}
  end

  def handle_call({:join, channel, params}, _from, socket) do
    socket =
      socket
      |> assign(:joined?, false)
      |> Slipstream.join(channel, params)

    {:reply, :ok, socket}
  end

  def handle_call(:status, _from, socket) do
    {:reply, :ok, socket}
  end

  def handle_call(:state, _from, socket) do
    {:reply, socket, socket}
  end

  @impl Slipstream
  def handle_disconnect(
        {:error, {:upgrade_failure, %{reason: %{status_code: 401} = reason}}},
        socket
      ) do
    socket =
      socket
      |> assign(:connecting?, false)
      |> assign(:error_code, reason.status_code)
      |> maybe_add_error_reasons(reason)

    {:ok, socket}
  end

  def handle_disconnect(:closed_by_remote, socket) do
    socket =
      socket
      |> assign(:connecting?, false)
      |> assign(:connected?, false)

    {:ok, socket}
  end

  defp maybe_add_error_reasons(socket, reason) do
    error_reason = Enum.find(reason.headers, fn {k, _v} -> k == "nh-connection-error-reason" end)

    if is_tuple(error_reason) do
      assign(socket, :error_reason, elem(error_reason, 1))
    else
      socket
    end
  end
end
