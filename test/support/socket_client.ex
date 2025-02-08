defmodule SocketClient do
  @moduledoc false

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
    GenServer.call(socket, :joined_device?)
  end

  def close(socket) do
    GenServer.stop(socket)
  end

  def reply(socket) do
    GenServer.call(socket, :reply)
  end

  def join_and_wait(socket, params \\ %{}) do
    GenServer.call(socket, {:join_and_wait, params})
  end

  def join_and_wait_extensions(socket, params \\ %{"geo" => "0.0.1", "health" => "0.0.1"}) do
    GenServer.call(socket, {:join_and_wait_extensions, params})
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

  def clean_close(socket) do
    GenServer.call(socket, :clean_close)
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

  @impl Slipstream
  def init(config) do
    Process.flag(:trap_exit, true)

    socket =
      new_socket()
      |> assign(:connected?, false)
      |> assign(:connecting?, true)
      |> assign(:joined_device?, false)
      |> assign(:joined_extensions?, false)
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

  @impl Slipstream
  def handle_connect(socket) do
    socket =
      socket
      |> assign(:connected?, true)
      |> assign(:connecting?, false)

    {:ok, socket}
  end

  @impl Slipstream
  def handle_join("device", reply, socket) do
    socket =
      socket
      |> assign(:joined_device?, true)
      |> assign(:reply, reply)

    {:ok, socket}
  end

  def handle_join("extensions", reply, socket) do
    socket =
      socket
      |> assign(:joined_extensions?, true)
      |> assign(:reply, reply)

    {:ok, socket}
  end

  @impl Slipstream
  def handle_message("device", "extensions:get", _message, socket) do
    {:ok, socket}
  end

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

  def handle_message("extensions", "health:check", %{}, socket) do
    socket =
      socket
      |> assign(:receive_check_helth?, true)

    {:ok, socket}
  end

  @impl Slipstream
  def handle_call(:connected?, _from, socket) do
    {:reply, socket.assigns.connected?, socket}
  end

  def handle_call(:connecting?, _from, socket) do
    {:reply, socket.assigns.connecting?, socket}
  end

  def handle_call(:joined_device?, _from, socket) do
    {:reply, socket.assigns.joined_device?, socket}
  end

  def handle_call(:joined_extensions?, _from, socket) do
    {:reply, socket.assigns.joined_extensions?, socket}
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

  def handle_call({:join, "device", params}, _from, socket) do
    socket =
      socket
      |> assign(:joined_device?, false)
      |> Slipstream.join("device", params)

    {:reply, :ok, socket}
  end

  def handle_call({:join, "extensions", params}, _from, socket) do
    socket =
      socket
      |> assign(:joined_extensions?, false)
      |> Slipstream.join("extensions", params)

    {:reply, :ok, socket}
  end

  def handle_call({:join_and_wait, params}, _from, socket) do
    socket =
      socket
      |> await_connect!()
      |> join("device", params)
      |> await_join!("device")
      |> assign(:connected?, true)
      |> assign(:joined_device?, true)
      |> assign(:reply, %{})

    {:reply, :ok, socket}
  end

  def handle_call({:join_and_wait_extensions, params}, _from, socket) do
    socket =
      socket
      |> await_connect!()
      |> join("extensions", params)
      |> await_join!("extensions")
      |> assign(:connected?, true)
      |> assign(:joined_extensions?, true)
      |> assign(:reply, %{})

    {:reply, :ok, socket}
  end

  def handle_call(:status, _from, socket) do
    {:reply, :ok, socket}
  end

  def handle_call(:state, _from, socket) do
    {:reply, socket, socket}
  end

  def handle_call(:clean_close, _from, socket) do
    socket =
      socket
      |> disconnect()
      |> await_disconnect!()
      |> assign(:connecting?, false)
      |> assign(:connected?, false)

    {:reply, :ok, socket}
  end

  @impl Slipstream
  def handle_disconnect(
        {:error, {:upgrade_failure, %{reason: reason}}},
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
