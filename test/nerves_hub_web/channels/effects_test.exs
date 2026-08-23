defmodule NervesHubWeb.Channels.EffectsTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.Channels.Effects
  alias Phoenix.Socket

  defp socket(), do: Effects.init(%Socket{})

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
      before = :erlang.system_info(:process_count)

      socket =
        Enum.reduce(1..50, socket(), fn i, socket ->
          Effects.apply_all(socket, [{:start_timer, {"health", i}, {Health, i}, 60_000}])
        end)

      assert :erlang.system_info(:process_count) - before == 0

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
