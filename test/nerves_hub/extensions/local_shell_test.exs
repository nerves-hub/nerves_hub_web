defmodule NervesHub.Extensions.LocalShellTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Consoles
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Extensions.LocalShell
  alias NervesHub.Extensions.State
  alias NervesHub.Fixtures
  alias NervesHub.Products.Notification
  alias Phoenix.Socket.Broadcast

  defp state(device_id) do
    State.new(%DeviceInfo{device_id: device_id, org_id: 1, product_id: 1})
  end

  defp state_for(product, identifier) do
    State.new(%DeviceInfo{
      device_id: device_id(),
      device_identifier: identifier,
      org_id: product.org_id,
      product_id: product.id
    })
  end

  defp product() do
    user = Fixtures.user_fixture()
    Fixtures.product_fixture(user, Fixtures.org_fixture(user))
  end

  defp device_id(), do: System.unique_integer([:positive])

  describe "attach/1" do
    test "tells the device page, asks the device for a shell and clears the scrollback" do
      id = device_id()
      :ok = Consoles.PubSub.subscribe_console_watcher(id)

      {_state, effects} = LocalShell.attach(state(id))

      assert_receive %Broadcast{event: "local_shell_attached"}, 500
      assert effects == [{:push, "local_shell:request_shell", %{}}, {:scrollback_clear}]
    end
  end

  describe "detach/1" do
    test "tells the device page the shell detached and clears the scrollback" do
      id = device_id()
      :ok = Consoles.PubSub.subscribe_console_watcher(id)

      {_state, effects} = LocalShell.detach(state(id))

      assert_receive %Broadcast{event: "local_shell_detached"}, 500
      assert effects == [{:scrollback_clear}]
    end
  end

  describe "handle_info/2 locate" do
    # Only an attached extension is handed messages, so answering is all there is
    # to it; `Extensions.Dispatch` is what keeps a detached shell quiet.
    test "answers the page that asked" do
      ref = make_ref()

      {_state, effects} = LocalShell.handle_info({:locate, self(), ref}, state(device_id()))

      assert_received {:local_shell_located, ^ref}
      assert effects == []
    end
  end

  # The device answers `request_shell` with how it went, and a failure leaves the
  # extension attached -- so the shell still reads as available and the UI offers
  # a shell that cannot work. Nothing else records it: before this, the reply hit
  # the catch-all below and was logged as an unknown message.
  describe "handle_in/3 request_status" do
    test "a failure is reported to the product" do
      product = product()
      state = state_for(product, "shell-fails-here")

      {_state, effects} =
        LocalShell.handle_in(
          "request_status",
          %{"status" => "failed", "reason" => "`:expty` not included in project dependencies"},
          state
        )

      assert effects == []

      assert [notification] = Repo.all(Notification)
      assert notification.level == :warning
      assert notification.message =~ "shell-fails-here"
      assert notification.message =~ "local_shell"
      assert notification.message =~ ":expty` not included in project dependencies"
      assert notification.metadata["extension"] == "local_shell"
    end

    test "the same failure again is counted rather than repeated" do
      product = product()
      state = state_for(product, "shell-fails-here")

      payload = %{"status" => "failed", "reason" => "no pty"}

      for _ <- 1..3, do: LocalShell.handle_in("request_status", payload, state)

      assert [notification] = Repo.all(Notification)
      assert notification.occurrence_count == 3
    end

    test "a different reason is its own notification, so the message matches it" do
      product = product()
      state = state_for(product, "shell-fails-here")

      LocalShell.handle_in("request_status", %{"status" => "failed", "reason" => "no pty"}, state)

      LocalShell.handle_in(
        "request_status",
        %{"status" => "failed", "reason" => "permission denied"},
        state
      )

      messages = Repo.all(Notification) |> Enum.map(& &1.message)

      assert length(messages) == 2
      assert Enum.any?(messages, &(&1 =~ "no pty"))
      assert Enum.any?(messages, &(&1 =~ "permission denied"))
    end

    test "a shell that started is neither reported nor logged as unknown" do
      product = product()
      state = state_for(product, "shell-works-here")

      {_state, effects} =
        LocalShell.handle_in("request_status", %{"status" => "started"}, state)

      assert effects == []
      assert Repo.all(Notification) == []
    end

    test "a reason longer than a notification should carry is cut short" do
      product = product()
      state = state_for(product, "shell-fails-here")

      LocalShell.handle_in(
        "request_status",
        %{"status" => "failed", "reason" => String.duplicate("a", 500)},
        state
      )

      assert [notification] = Repo.all(Notification)
      assert String.length(notification.metadata["reason"]) == 200
      assert String.ends_with?(notification.metadata["reason"], "…")
    end
  end
end
