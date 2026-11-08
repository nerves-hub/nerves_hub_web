defmodule NervesHub.DeviceLink.Dispatcher.RemoteFailureTest do
  @moduledoc """
  How the remote dispatcher fails, against real nodes.

  What it decides turns on how a call failed, and the two failures that matter
  only exist between nodes: a node that cannot be reached, and one that took the
  call and is slow to answer. So these start two peer nodes standing in for
  platform nodes, each with a stub `NervesHub.DeviceLink`, and take this node
  out of the ring so that every call goes to one of them.
  """

  use ExUnit.Case, async: false

  alias NervesHub.DeviceLink.Dispatcher.NoHandlersError
  alias NervesHub.DeviceLink.Dispatcher.Remote
  alias NervesHub.DeviceLink.Dispatcher.TimeoutError
  alias NervesHub.DeviceLink.Handlers

  # Compiled on each peer. Every call reports itself to the test, then does
  # whatever the test asked that peer to do.
  @stub """
  defmodule NervesHub.DeviceLink do
    def connect(device_info, ip_address),
      do: RemoteDispatchStub.handle(:connect, [device_info, ip_address])
  end

  defmodule RemoteDispatchStub do
    def join(scope, group) do
      parent = self()

      pid =
        spawn(fn ->
          :ok = :pg.join(scope, group, self())
          send(parent, :joined)

          receive do
            :leave -> :ok
          end
        end)

      receive do
        :joined -> :ok
      end

      Process.register(pid, __MODULE__.Member)
      :ok
    end

    def leave() do
      ref = Process.monitor(__MODULE__.Member)
      send(__MODULE__.Member, :leave)

      receive do
        {:DOWN, ^ref, _, _, _} -> :ok
      end
    end

    def set(test_pid, behaviour) do
      :persistent_term.put(__MODULE__, {test_pid, behaviour})
    end

    def handle(function, _args) do
      {test_pid, behaviour} = :persistent_term.get(__MODULE__)
      send(test_pid, {:called, node(), function})

      case behaviour do
        :answer ->
          {:answered_by, node()}

        {:sleep, ms} ->
          Process.sleep(ms)
          {:answered_by, node()}

        :disconnect ->
          true = :erlang.disconnect_node(node(test_pid))
          Process.sleep(:infinity)

        :raise ->
          raise ArgumentError, "the platform raised"
      end
    end
  end
  """

  setup_all do
    started_distribution? = ensure_distributed()

    peers =
      for _ <- 1..2 do
        {:ok, pid, name} = start_peer()
        {pid, name}
      end

    on_exit(fn ->
      Enum.each(peers, fn {pid, _name} -> :peer.stop(pid) end)
      if started_distribution?, do: Node.stop()
    end)

    %{peers: peers}
  end

  setup %{peers: peers} do
    previous = Application.get_env(:nerves_hub, Remote)
    Application.put_env(:nerves_hub, Remote, timeout: 200, attempts: 2)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:nerves_hub, Remote, previous),
        else: Application.delete_env(:nerves_hub, Remote)
    end)

    # This node is a handler too. :pg memberships are a multiset, so clear every
    # one and restore a single canonical join afterwards.
    handler = Process.whereis(Handlers)
    on_exit(fn -> :pg.join(Handlers.scope(), :handlers, handler) end)

    Handlers.scope()
    |> :pg.get_members(:handlers)
    |> Enum.filter(&(node(&1) == node()))
    |> Enum.each(&:pg.leave(Handlers.scope(), :handlers, &1))

    # A test that disconnects a peer leaves it disconnected. Reconnect, and wait
    # for :pg to see both handlers again.
    for {pid, name} <- peers do
      true = Node.connect(name)
      :ok = :peer.call(pid, RemoteDispatchStub, :set, [self(), :answer])
    end

    names = Enum.map(peers, &elem(&1, 1))
    :ok = wait_until(fn -> Enum.sort(Handlers.nodes()) == Enum.sort(names) end)

    # Name the peers by the order a call for this device will try them in.
    device_id = 1234
    [first, second] = Handlers.ordered(device_id)

    peer = Map.new(peers, fn {pid, name} -> {name, pid} end)

    attach_telemetry()

    %{device_id: device_id, first: {first, peer[first]}, second: {second, peer[second]}}
  end

  describe "a node that cannot be reached" do
    test "the call is retried on the next node, and the next node answers", ctx do
      %{first: {first, first_pid}, second: {second, _}} = ctx
      behave(first_pid, :disconnect)

      assert Remote.call(:connect, [%{device_id: ctx.device_id}, nil]) == {:answered_by, second}

      assert_received {:called, ^first, :connect}
      assert_received {:called, ^second, :connect}

      assert_received {:telemetry, [:nerves_hub, :device_link, :dispatch_failure],
                       %{node: ^first, reason: :noconnection, function: :connect}}
    end

    test "raises NoHandlersError when the attempts run out", ctx do
      Application.put_env(:nerves_hub, Remote, timeout: 200, attempts: 1)
      %{first: {first, first_pid}, second: {second, _}} = ctx
      behave(first_pid, :disconnect)

      assert_raise NoHandlersError, ~r/connect/, fn ->
        Remote.call(:connect, [%{device_id: ctx.device_id}, nil])
      end

      assert_received {:called, ^first, :connect}
      refute_received {:called, ^second, _}
    end
  end

  describe "a node that is slow to answer" do
    test "raises TimeoutError and never sends the call to another node", ctx do
      %{first: {first, first_pid}, second: {second, _}} = ctx
      behave(first_pid, {:sleep, 500})

      error =
        assert_raise TimeoutError, fn ->
          Remote.call(:connect, [%{device_id: ctx.device_id}, nil])
        end

      assert %TimeoutError{function: :connect, node: ^first, timeout: 200} = error
      assert Exception.message(error) =~ "did not finish"

      assert_received {:called, ^first, :connect}

      assert_received {:telemetry, [:nerves_hub, :device_link, :dispatch_timeout],
                       %{node: ^first, timeout: 200, function: :connect}}

      refute_received {:telemetry, [:nerves_hub, :device_link, :dispatch_failure], _}

      # Long enough for the first node to finish what it was still doing, and for
      # any second copy to have shown up.
      refute_receive {:called, ^second, _}, 600
    end
  end

  describe "no node at all" do
    test "raises NoHandlersError without calling anything", ctx do
      for {_name, pid} <- [ctx.first, ctx.second],
          do: :peer.call(pid, RemoteDispatchStub, :leave, [])

      :ok = wait_until(fn -> Handlers.nodes() == [] end)

      on_exit(fn ->
        for {_name, pid} <- [ctx.first, ctx.second] do
          :peer.call(pid, RemoteDispatchStub, :join, [Handlers.scope(), :handlers])
        end
      end)

      assert_raise NoHandlersError, fn ->
        Remote.call(:connect, [%{device_id: ctx.device_id}, nil])
      end

      refute_received {:called, _, _}
    end
  end

  describe "the platform raising" do
    test "propagates, and is not retried", ctx do
      %{first: {first, first_pid}, second: {second, _}} = ctx
      behave(first_pid, :raise)

      assert {:exception, %ArgumentError{message: "the platform raised"}, _stack} =
               catch_error(Remote.call(:connect, [%{device_id: ctx.device_id}, nil]))

      assert_received {:called, ^first, :connect}
      refute_received {:called, ^second, _}
      refute_received {:telemetry, _, _}
    end
  end

  # ------------------------------------------------------------------ helpers

  defp behave(peer_pid, behaviour), do: :ok = :peer.call(peer_pid, RemoteDispatchStub, :set, [self(), behaviour])

  defp ensure_distributed() do
    if Node.alive?() do
      false
    else
      # Node.start/2 needs epmd and does not start it.
      {_, 0} = System.cmd("epmd", ["-daemon"], env: [])
      {:ok, _} = Node.start(:"remote_dispatch_test@127.0.0.1", :longnames)
      true
    end
  end

  # Controlled over stdio rather than distribution, so that a test can drop the
  # distribution connection without taking the peer down with it.
  #
  # Kept out of :global's mesh, too. Left in it, the peers connect to each other,
  # and when one drops this node the other is told and -- preventing overlapping
  # partitions -- disconnects from this node as well. The retry then finds no
  # node to go to, but only sometimes, depending on which gets there first.
  defp start_peer() do
    code_path = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

    kernel = [
      ~c"-kernel",
      ~c"connect_all",
      ~c"false",
      ~c"-kernel",
      ~c"prevent_overlapping_partitions",
      ~c"false"
    ]

    {:ok, pid, name} =
      :peer.start(%{
        name: :peer.random_name(~c"remote_dispatch_peer"),
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        args: [~c"-setcookie", Atom.to_charlist(Node.get_cookie())] ++ kernel ++ code_path
      })

    {:ok, _} = :peer.call(pid, :application, :ensure_all_started, [:elixir])
    # The real NervesHub.DeviceLink is on the code path too. Replacing it is the
    # point, so the conflict is not worth a warning.
    :ok = :peer.call(pid, Code, :put_compiler_option, [:ignore_module_conflict, true])
    _ = :peer.call(pid, Code, :compile_string, [@stub])
    {:ok, _} = :peer.call(pid, :pg, :start, [Handlers.scope()])
    :ok = :peer.call(pid, RemoteDispatchStub, :join, [Handlers.scope(), :handlers])

    {:ok, pid, name}
  end

  defp attach_telemetry() do
    test = self()
    id = "remote-dispatch-test-#{inspect(make_ref())}"

    :telemetry.attach_many(
      id,
      [
        [:nerves_hub, :device_link, :dispatch_failure],
        [:nerves_hub, :device_link, :dispatch_timeout]
      ],
      fn event, _measurements, metadata, _config -> send(test, {:telemetry, event, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  defp wait_until(fun, attempts \\ 100) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        {:error, :timeout}

      true ->
        Process.sleep(20)
        wait_until(fun, attempts - 1)
    end
  end
end
