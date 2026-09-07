defmodule NervesHub.DeviceLink.DispatcherTest do
  @moduledoc """
  The seam that decides where DeviceLink calls run.

  Worth testing despite being small: a wrong config key here fails silently by
  continuing to run everything locally, which is exactly the failure that would
  not show up until a caller without a database tried to use it.
  """

  use ExUnit.Case, async: false

  alias NervesHub.DeviceLink
  alias NervesHub.DeviceLink.Client
  alias NervesHub.DeviceLink.Dispatcher

  defmodule Recorder do
    @moduledoc false
    @behaviour NervesHub.DeviceLink.Dispatcher

    alias NervesHub.DeviceLink.Dispatcher

    @impl Dispatcher
    def call(function, args) do
      send(self(), {:dispatched, function, args})
      :recorded
    end
  end

  setup do
    # Restore rather than delete: the suite can be run with dispatch configured
    # (DEVICE_LINK_DISPATCH=remote), and deleting it would leave later tests
    # running against a different implementation than they were started with.
    previous = Application.fetch_env(:nerves_hub, Dispatcher)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:nerves_hub, Dispatcher, value)
        :error -> Application.delete_env(:nerves_hub, Dispatcher)
      end
    end)

    :ok
  end

  test "runs locally unless told otherwise" do
    Application.delete_env(:nerves_hub, Dispatcher)

    assert Dispatcher.impl() == Dispatcher.Local
  end

  test "local dispatch reaches DeviceLink itself" do
    assert Dispatcher.call(:shared_secrets_enabled?, []) == DeviceLink.shared_secrets_enabled?()
  end

  test "the configured implementation replaces local dispatch" do
    Application.put_env(:nerves_hub, Dispatcher, Recorder)

    assert Dispatcher.call(:heartbeat, ["some-ref"]) == :recorded
    assert_received {:dispatched, :heartbeat, ["some-ref"]}
  end

  describe "every Client function goes through the dispatcher" do
    setup do
      Application.put_env(:nerves_hub, Dispatcher, Recorder)
    end

    test "connection lifecycle" do
      assert Client.authenticate({:ssl_cert, "der"}) == :recorded
      assert_received {:dispatched, :authenticate, [{:ssl_cert, "der"}]}

      assert Client.connect(:device_info, "203.0.113.7") == :recorded
      assert_received {:dispatched, :connect, [:device_info, "203.0.113.7"]}

      assert Client.heartbeat("ref") == :recorded
      assert_received {:dispatched, :heartbeat, ["ref"]}

      assert Client.disconnect("ref") == :recorded
      assert_received {:dispatched, :disconnect, ["ref", nil]}
    end

    test "device link" do
      assert Client.device_join(:device_info, %{}) == :recorded
      assert_received {:dispatched, :device_join, [:device_info, %{}]}

      assert Client.device_message(:session, "event", %{}) == :recorded
      assert_received {:dispatched, :device_message, [:session, "event", %{}]}

      assert Client.device_notify(:session, :message) == :recorded
      assert_received {:dispatched, :device_notify, [:session, :message]}

      assert Client.device_broadcast(:session, "updated", %{}) == :recorded
      assert_received {:dispatched, :device_broadcast, [:session, "updated", %{}]}
    end

    test "extensions" do
      assert Client.extensions_join(:device_info, %{}) == :recorded
      assert_received {:dispatched, :extensions_join, [:device_info, %{}]}

      assert Client.extension_message(:extensions, "health:report", %{}) == :recorded
      assert_received {:dispatched, :extension_message, [:extensions, "health:report", %{}]}

      assert Client.extension_info(:extensions, SomeModule, :msg) == :recorded
      assert_received {:dispatched, :extension_info, [:extensions, SomeModule, :msg]}
    end
  end

  test "the Client covers exactly what DeviceLink exposes for dispatch" do
    # If a function is added to Client without DeviceLink implementing it, local
    # dispatch would fail at runtime rather than here.
    {:module, _} = Code.ensure_loaded(DeviceLink)

    for {function, arity} <- Client.__info__(:functions) do
      # Client arities match DeviceLink's, except disconnect/1 which defaults its reason.
      assert function_exported?(DeviceLink, function, arity) or
               function_exported?(DeviceLink, function, arity + 1),
             "DeviceLink does not implement #{function}/#{arity}"
    end
  end
end
