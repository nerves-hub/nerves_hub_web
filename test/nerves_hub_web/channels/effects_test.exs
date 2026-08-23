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
    test "delivers the message and keeps delivering it once re-armed" do
      socket = Effects.apply_all(socket(), [{:start_timer, {"health", :check}, {Health, :check}, 20}])

      assert_receive {Health, :check}, 500

      # The channel re-arms on delivery; that is what makes it repeat.
      socket = Effects.reschedule(socket, {Health, :check})
      assert_receive {Health, :check}, 500

      _ = Effects.reschedule(socket, {Health, :check})
      assert_receive {Health, :check}, 500
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

      # `Process.send_after/3` hands back a bare reference. `:timer` hands back
      # `{:interval, ref}`, so this tells the two apart without counting
      # anything.
      for {_key, timer} <- socket.assigns.link_timers do
        assert {:interval, ref, {Health, _}, 60_000} = timer
        assert is_reference(ref)
      end

      # and they are all still cancellable
      Enum.reduce(1..50, socket, fn i, socket ->
        Effects.apply_all(socket, [{:cancel_timer, {"health", i}}])
      end)
    end

    test "cancelling stops the repeat" do
      socket = Effects.apply_all(socket(), [{:start_timer, {"health", :check}, {Health, :check}, 20}])

      assert_receive {Health, :check}, 500

      socket = Effects.reschedule(socket, {Health, :check})
      _socket = Effects.apply_all(socket, [{:cancel_timer, {"health", :check}}])

      refute_receive {Health, :check}, 200
    end

    test "re-arming a message that is not a live timer changes nothing" do
      socket = socket()

      assert Effects.reschedule(socket, {Health, :check}) == socket
      refute_receive {Health, :check}, 100
    end

    test "starting the same key twice does not leave the first timer running" do
      socket = Effects.apply_all(socket(), [{:start_timer, {"health", :check}, {Health, :first}, 50}])
      socket = Effects.apply_all(socket, [{:start_timer, {"health", :check}, {Health, :second}, 50}])

      assert_receive {Health, :second}, 500
      refute_received {Health, :first}

      _ = socket
    end
  end
end
