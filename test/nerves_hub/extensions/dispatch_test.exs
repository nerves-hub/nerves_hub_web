defmodule NervesHub.Extensions.DispatchTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Extensions.Dispatch
  alias NervesHub.Fixtures
  alias NervesHub.Products.Notification

  defp product() do
    user = Fixtures.user_fixture()
    Fixtures.product_fixture(user, Fixtures.org_fixture(user))
  end

  defp attached(product, identifier) do
    device_info = %DeviceInfo{
      device_id: System.unique_integer([:positive]),
      device_identifier: identifier,
      org_id: product.org_id,
      product_id: product.id,
      allowed_extensions: [:health, :local_shell]
    }

    {attach_list, extensions} = Dispatch.join(device_info, %{"local_shell" => "0.0.1"})

    assert "local_shell" in attach_list

    extensions
  end

  # A device that cannot start an extension says so and carries on connected.
  # The extension is detached here and nothing else records it, so without this
  # the only trace is a log line on whichever node serviced the call.
  describe "an extension the device could not start" do
    test "is reported to the product" do
      product = product()
      extensions = attached(product, "cannot-start-here")

      {:ok, extensions, effects} =
        Dispatch.message(extensions, "local_shell:error", %{"reason" => "start_failure"})

      assert effects == []
      assert extensions["local_shell"].status == :detached

      assert [notification] = Repo.all(Notification)
      assert notification.level == :warning
      assert notification.message =~ "cannot-start-here"
      assert notification.message =~ "start_failure"
      assert notification.metadata["extension"] == "local_shell"
    end

    test "is reported even when the device names no reason" do
      # `nerves_hub_link` sends one, but the notification is the point rather
      # than the reason, and a client that omits it should not be silent.
      product = product()
      extensions = attached(product, "quietly-broken")

      {:ok, _extensions, _effects} = Dispatch.message(extensions, "local_shell:error", %{})

      assert [notification] = Repo.all(Notification)
      assert notification.metadata["reason"] == nil
      refute notification.message =~ "extension:"
    end

    test "detaching normally is not a failure" do
      product = product()
      extensions = attached(product, "detaches-cleanly")

      {:ok, extensions, _effects} = Dispatch.message(extensions, "local_shell:detached", %{})

      assert extensions["local_shell"].status == :detached
      assert Repo.all(Notification) == []
    end

    test "attaching normally is not a failure" do
      product = product()
      extensions = attached(product, "attaches-cleanly")

      {:ok, extensions, effects} = Dispatch.message(extensions, "local_shell:attached", %{})

      assert extensions["local_shell"].status == :attached
      assert {:push, "local_shell:request_shell", %{}} in effects
      assert Repo.all(Notification) == []
    end
  end
end
