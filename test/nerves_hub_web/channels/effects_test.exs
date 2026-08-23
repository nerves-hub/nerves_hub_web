defmodule NervesHubWeb.Channels.EffectsTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.Channels.Effects
  alias Phoenix.Socket

  defp socket(), do: Effects.init(%Socket{})

  defp timer_processes() do
    Enum.count(Process.list(), fn pid ->
      match?({:current_function, {:timer, :interval_loop, _}}, Process.info(pid, :current_function))
    end)
  end

  describe "repeating timers" do
    test "delivers in an envelope and keeps delivering once each firing is handed back" do
      socket = Effects.apply_all(socket(), [{:start_timer, {"health", :check}, {Health, :check}, 20}])

      assert_receive {:timeout, _ref, _payload} = timer, 500
      assert {:deliver, {Health, :check}, socket} = Effects.timer_fired(socket, timer)

      # The hand-back is what re-arms it; that is what makes it repeat.
      assert_receive {:timeout, _ref, _payload} = timer, 500
      assert {:deliver, {Health, :check}, socket} = Effects.timer_fired(socket, timer)

      assert_receive {:timeout, _ref, _payload} = timer, 500
      assert {:deliver, {Health, :check}, _socket} = Effects.timer_fired(socket, timer)
    end

    test "costs no process, unlike :timer.send_interval/2" do
      before = timer_processes()

      socket =
        Enum.reduce(1..50, socket(), fn i, socket ->
          Effects.apply_all(socket, [{:start_timer, {"health", i}, {Health, i}, 60_000}])
        end)

      # Counting `:timer.interval_loop` processes rather than every process on
      # the node: the suite runs async, so a total is other tests' noise.
      assert timer_processes() == before

      # `:erlang.start_timer/3` hands back a bare reference. `:timer` hands
      # back `{:interval, ref}`, so this tells the two apart without counting
      # anything.
      for {_key, timer} <- socket.assigns.link_timers do
        assert {:interval, ref, 60_000} = timer
        assert is_reference(ref)
      end

      # and they are all still cancellable
      Enum.reduce(1..50, socket, fn i, socket ->
        Effects.apply_all(socket, [{:cancel_timer, {"health", i}}])
      end)
    end

    test "cancelling stops the repeat" do
      socket = Effects.apply_all(socket(), [{:start_timer, {"health", :check}, {Health, :check}, 20}])

      assert_receive {:timeout, _ref, _payload} = timer, 500
      assert {:deliver, {Health, :check}, socket} = Effects.timer_fired(socket, timer)

      _socket = Effects.apply_all(socket, [{:cancel_timer, {"health", :check}}])

      refute_receive {:timeout, _ref, _payload}, 200
    end

    test "a tick carrying the same message as the interval cannot pass for it firing" do
      # `Extensions.Health.attach/1` asks for a report now and then every
      # interval, both as the same term. Only the envelope counts as a firing.
      message = {Health, :check}

      socket =
        Effects.apply_all(socket(), [
          {:send_self, message},
          {:start_timer, {"health", :check}, message, 100}
        ])

      # The tick arrives bare and must not be claimed as a timer delivery.
      assert_receive ^message, 50
      assert Effects.timer_fired(socket, message) == :not_timer

      # One delivery per interval, nothing in between.
      assert_receive {:timeout, _ref, _payload} = timer, 500
      refute_receive _anything, 50
      assert {:deliver, ^message, socket} = Effects.timer_fired(socket, timer)

      assert_receive {:timeout, _ref, _payload} = timer, 500
      refute_receive _anything, 50
      assert {:deliver, ^message, _socket} = Effects.timer_fired(socket, timer)
    end

    test "a delivery from a timer cancelled after firing is dropped" do
      socket = Effects.apply_all(socket(), [{:start_timer, {"health", :check}, {Health, :check}, 10}])

      assert_receive {:timeout, _ref, _payload} = timer, 500
      socket = Effects.apply_all(socket, [{:cancel_timer, {"health", :check}}])

      assert {:drop, _socket} = Effects.timer_fired(socket, timer)
    end

    test "a delivery from a timer replaced after firing is dropped" do
      socket = Effects.apply_all(socket(), [{:start_timer, {"health", :check}, {Health, :check}, 10}])

      assert_receive {:timeout, _ref, _payload} = stale, 500
      socket = Effects.apply_all(socket, [{:start_timer, {"health", :check}, {Health, :check}, 60_000}])

      # Same key, same message — only the ref tells the stale firing apart.
      assert {:drop, _socket} = Effects.timer_fired(socket, stale)
    end

    test "a message that is not a timer delivery is not claimed" do
      assert Effects.timer_fired(socket(), {Health, :check}) == :not_timer
      refute_receive _anything, 50
    end
  end

  describe "one-shot timers" do
    test "delivers once and retires its bookkeeping" do
      socket = Effects.apply_all(socket(), [{:send_after, {:script_ref, "abc"}, {:clear_script_ref, "abc"}, 10}])

      assert_receive {:timeout, _ref, _payload} = timer, 500
      assert {:deliver, {:clear_script_ref, "abc"}, socket} = Effects.timer_fired(socket, timer)

      # Fired means done — nothing left to cancel.
      assert socket.assigns.link_timers == %{}
      refute_receive {:timeout, _ref, _payload}, 100
    end

    test "cancelling before it fires stops the delivery" do
      socket = Effects.apply_all(socket(), [{:send_after, {:script_ref, "abc"}, {:clear_script_ref, "abc"}, 50}])
      socket = Effects.apply_all(socket, [{:cancel_timer, {:script_ref, "abc"}}])

      assert socket.assigns.link_timers == %{}
      refute_receive {:timeout, _ref, _payload}, 200
    end
  end
end
