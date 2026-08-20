defmodule NervesHub.Devices.ExternalIdentitiesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices
  alias NervesHub.Devices.ExternalIdentities
  alias NervesHub.Devices.ExternalIdentity
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok, %{device: device, org: org, product: product, firmware: firmware, user: user}}
  end

  describe "report/3" do
    test "records an identity a device reports about itself", %{device: device} do
      assert {:ok, identity} =
               ExternalIdentities.report(device.id, "iroh", %{
                 identifier: "a1b2c3",
                 details: %{"ticket" => "some-ticket"}
               })

      assert identity.service == :iroh
      assert identity.identifier == "a1b2c3"
      assert identity.details == %{"ticket" => "some-ticket"}
      assert identity.source == :device_reported
      assert identity.last_reported_at
    end

    test "replaces the previous value rather than accumulating rows", %{device: device} do
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "first"})
      {:ok, updated} = ExternalIdentities.report(device.id, "iroh", %{identifier: "second"})

      assert updated.identifier == "second"
      assert [%ExternalIdentity{identifier: "second"}] = ExternalIdentities.list_for_device(device.id)
    end

    test "a device can hold identities on several services at once", %{device: device} do
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "iroh-key"})
      {:ok, _} = ExternalIdentities.report(device.id, "tailscale", %{identifier: "ts-key"})

      assert [%{service: :iroh}, %{service: :tailscale}] =
               ExternalIdentities.list_for_device(device.id)
    end

    test "accepts an atom service as well as a string", %{device: device} do
      assert {:ok, identity} =
               ExternalIdentities.report(device.id, :netbird, %{identifier: "nb-key"})

      assert identity.service == :netbird
    end

    test "refuses a service this NervesHub doesn't know", %{device: device} do
      assert {:error, :unsupported_service} =
               ExternalIdentities.report(device.id, "zerotier", %{identifier: "zt-key"})

      assert ExternalIdentities.list_for_device(device.id) == []
    end

    test "refuses a service name that is an atom but not a known one", %{device: device} do
      # :erlang is certainly an existing atom, which is exactly why casting can't
      # lean on String.to_existing_atom/1.
      assert {:error, :unsupported_service} =
               ExternalIdentities.report(device.id, :erlang, %{identifier: "nope"})
    end

    test "two devices cannot claim the same key", %{device: device, org: org, product: product, firmware: firmware} do
      # A cloned SD card gives a whole batch the identity of the device that was
      # imaged. The second device to report is the one that fails.
      other = Fixtures.device_fixture(org, product, firmware, %{identifier: "cloned-sibling"})

      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "shared-key"})

      assert {:error, changeset} =
               ExternalIdentities.report(other.id, "iroh", %{identifier: "shared-key"})

      refute changeset.valid?
    end

    test "the same key on different services is fine", %{device: device} do
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "same-bytes"})

      assert {:ok, _} =
               ExternalIdentities.report(device.id, "wireguard", %{identifier: "same-bytes"})
    end

    test "refuses an identifier longer than the column allows", %{device: device} do
      assert {:error, changeset} =
               ExternalIdentities.report(device.id, "iroh", %{
                 identifier: String.duplicate("a", 256)
               })

      assert "should be at most 255 character(s)" in errors_on(changeset).identifier
    end

    test "refuses an oversized details payload", %{device: device} do
      # `details` is written from a device-supplied map, so it needs a ceiling.
      huge = %{"blob" => String.duplicate("x", ExternalIdentity.max_details_bytes() + 1)}

      assert {:error, changeset} =
               ExternalIdentities.report(device.id, "iroh", %{identifier: "ok", details: huge})

      assert changeset.errors[:details]
    end

    test "requires an identifier", %{device: device} do
      assert {:error, changeset} = ExternalIdentities.report(device.id, "iroh", %{details: %{}})
      assert "can't be blank" in errors_on(changeset).identifier
    end
  end

  describe "two endpoints of the same service" do
    test "coexist as separate identities", %{device: device} do
      # A device can run an iroh console and an iroh application, each holding
      # its own key. Both are iroh; they are not the same identity.
      {:ok, _} =
        ExternalIdentities.report(device.id, "iroh", %{
          instance: "iroh_console",
          identifier: "console-key"
        })

      {:ok, _} =
        ExternalIdentities.report(device.id, "iroh", %{
          instance: "app_sync",
          identifier: "app-key"
        })

      assert [%{instance: "app_sync"}, %{instance: "iroh_console"}] =
               ExternalIdentities.list_for_device(device.id)
    end

    test "a rotated key updates its row rather than accumulating a dead one", %{device: device} do
      # This is why the instance exists rather than telling endpoints apart by
      # identifier: keying on the value being tracked would leave the old key
      # behind forever with nothing marking it stale.
      {:ok, first} =
        ExternalIdentities.report(device.id, "iroh", %{
          instance: "iroh_console",
          identifier: "key-before-rotation"
        })

      {:ok, second} =
        ExternalIdentities.report(device.id, "iroh", %{
          instance: "iroh_console",
          identifier: "key-after-rotation"
        })

      assert first.id == second.id
      assert [%{identifier: "key-after-rotation"}] = ExternalIdentities.list_for_device(device.id)
    end

    test "one device cannot report the same key under two instances", %{device: device} do
      {:ok, _} =
        ExternalIdentities.report(device.id, "iroh", %{instance: "one", identifier: "same-key"})

      assert {:error, changeset} =
               ExternalIdentities.report(device.id, "iroh", %{
                 instance: "two",
                 identifier: "same-key"
               })

      refute changeset.valid?
    end

    test "get/3 finds the endpoint asked for", %{device: device} do
      {:ok, _} =
        ExternalIdentities.report(device.id, "iroh", %{instance: "console", identifier: "a"})

      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{instance: "sync", identifier: "b"})

      assert {:ok, %{identifier: "a"}} = ExternalIdentities.get(device.id, :iroh, "console")
      assert {:ok, %{identifier: "b"}} = ExternalIdentities.get(device.id, :iroh, "sync")
      assert ExternalIdentities.get(device.id, :iroh) == {:error, :not_found}
    end
  end

  describe "the instance a device reports" do
    test "defaults when a device doesn't name one", %{device: device} do
      # Most services are singletons; a device running one of something
      # shouldn't have to say so.
      assert {:ok, identity} = ExternalIdentities.report(device.id, "iroh", %{identifier: "solo"})

      assert identity.instance == ExternalIdentity.default_instance()
      assert {:ok, ^identity} = ExternalIdentities.get(device.id, :iroh)
    end

    test "blank and unusable values fall back to the default", %{device: device} do
      # Each of these lands on the same default-instance row, so they update it
      # rather than colliding — which is the point.
      for {instance, label} <- [{"", "empty"}, {"   ", "whitespace"}, {nil, "nil"}, {123, "number"}] do
        assert {:ok, identity} =
                 ExternalIdentities.report(device.id, "iroh", %{
                   instance: instance,
                   identifier: "key-#{label}"
                 })

        assert identity.instance == ExternalIdentity.default_instance(),
               "a #{label} instance should have fallen back to the default"
      end

      assert length(ExternalIdentities.list_for_device(device.id)) == 1
    end

    test "is trimmed", %{device: device} do
      assert {:ok, identity} =
               ExternalIdentities.report(device.id, "iroh", %{
                 instance: "  iroh_console  ",
                 identifier: "trimmed"
               })

      assert identity.instance == "iroh_console"
    end

    test "an atom instance is accepted", %{device: device} do
      assert {:ok, identity} =
               ExternalIdentities.report(device.id, "iroh", %{
                 instance: :iroh_console,
                 identifier: "atom-instance"
               })

      assert identity.instance == "iroh_console"
    end
  end

  describe "report/3 against an operator-recorded identity" do
    setup %{device: device} do
      identity =
        Fixtures.external_identity_fixture(device, %{
          service: :iroh,
          identifier: "operator-recorded",
          source: :operator
        })

      %{identity: identity}
    end

    test "a device claiming a different identity is refused, not silently applied", %{device: device} do
      # This disagreement is the signal — a reflashed device, a wiped data
      # partition, or something claiming to be this device.
      assert {:error, :operator_managed} =
               ExternalIdentities.report(device.id, "iroh", %{identifier: "device-claims-this"})

      assert {:ok, unchanged} = ExternalIdentities.get(device.id, :iroh)
      assert unchanged.identifier == "operator-recorded"
      assert unchanged.source == :operator
    end

    test "a device agreeing is recorded as having been heard from", %{device: device, identity: identity} do
      assert {:ok, touched} =
               ExternalIdentities.report(device.id, "iroh", %{identifier: "operator-recorded"})

      assert touched.source == :operator
      assert DateTime.compare(touched.last_reported_at, identity.last_reported_at) in [:gt, :eq]
    end
  end

  describe "get/2 and list_for_device/1" do
    test "get/2 reports a missing identity rather than raising", %{device: device} do
      assert ExternalIdentities.get(device.id, :iroh) == {:error, :not_found}
    end

    test "list_for_device/1 is empty for a device that has reported nothing", %{device: device} do
      assert ExternalIdentities.list_for_device(device.id) == []
    end

    test "identities are scoped to their own device", %{device: device, org: org, product: product, firmware: firmware} do
      other = Fixtures.device_fixture(org, product, firmware, %{identifier: "some-other-device"})

      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "mine"})

      assert ExternalIdentities.list_for_device(other.id) == []
    end
  end

  describe "deleting a device" do
    test "takes its external identities with it", %{device: device} do
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "goes-away"})

      {:ok, _device} = Devices.delete_device(device)

      assert ExternalIdentities.list_for_device(device.id) == []
    end

    test "frees the key so the same hardware can be reprovisioned", %{
      device: device,
      org: org,
      product: product,
      firmware: firmware
    } do
      # A device is only soft deleted, so without an explicit cleanup its rows
      # would keep holding the (service, identifier) index forever.
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "reused-key"})
      {:ok, _} = Devices.delete_device(device)

      replacement = Fixtures.device_fixture(org, product, firmware, %{identifier: "replacement"})

      assert {:ok, _} =
               ExternalIdentities.report(replacement.id, "iroh", %{identifier: "reused-key"})
    end
  end

  describe "broadcasts" do
    test "tells the device page when an identity changes", %{device: device} do
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "internal:device:#{device.id}")

      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "first"})
      assert_receive %Broadcast{event: "external_identities:updated"}

      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "changed"})
      assert_receive %Broadcast{event: "external_identities:updated"}
    end

    test "stays quiet when a device re-reports what we already had", %{device: device} do
      # Devices report on every reconnect. Re-rendering every open device page
      # each time would be pure noise.
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "steady"})

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "internal:device:#{device.id}")

      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "steady"})

      refute_receive %Broadcast{event: "external_identities:updated"}, 100
    end
  end

  describe "get_device_by_identifier/2" do
    test "finds the device that reported the key", %{device: device, org: org, product: product} do
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "abc123"})

      assert {:ok, found} = ExternalIdentities.get_device_by_identifier(:iroh, "abc123")

      assert found.device_id == device.id
      assert found.device_identifier == device.identifier
      assert found.org_id == org.id
      assert found.product_id == product.id
      assert found.service == :iroh
      assert found.instance == ExternalIdentity.default_instance()
    end

    test "accepts the service as a string, as an :erpc caller would send it", %{device: device} do
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "abc123"})

      assert {:ok, found} = ExternalIdentities.get_device_by_identifier("iroh", "abc123")
      assert found.device_id == device.id
    end

    test "returns a plain map, not a schema struct", %{device: device} do
      # The caller runs on a node with no NervesHub modules loaded, where a
      # struct is a map carrying a __struct__ key pointing at nothing. See the
      # cross-application contract note in AGENTS.md.
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "abc123"})

      assert {:ok, found} = ExternalIdentities.get_device_by_identifier(:iroh, "abc123")

      refute is_struct(found)
      refute Map.has_key?(found, :__struct__)
    end

    test "returns exactly the published keys", %{device: device} do
      # Pins the shape for callers this repository cannot see and will not fail
      # to compile against. Adding a key here is safe; removing or renaming one
      # is a breaking change needing a coordinated release.
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "abc123"})

      assert {:ok, found} = ExternalIdentities.get_device_by_identifier(:iroh, "abc123")

      assert found |> Map.keys() |> Enum.sort() == [
               :device_id,
               :device_identifier,
               :instance,
               :org_id,
               :product_id,
               :service
             ]
    end

    test "returns not_found for a key nobody registered", %{device: device} do
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "abc123"})

      assert {:error, :not_found} =
               ExternalIdentities.get_device_by_identifier(:iroh, "never-registered")
    end

    test "deleting a device takes its identities with it", %{device: device} do
      # delete_device/1 soft deletes the device but removes the identity rows
      # outright, so the key stops resolving rather than resolving to a deleted
      # device. It has to: the rows hold the (service, identifier) unique index,
      # and reprovisioning the same hardware would otherwise collide.
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "abc123"})
      {:ok, _} = Devices.delete_device(device)

      assert {:error, :not_found} = ExternalIdentities.get_device_by_identifier(:iroh, "abc123")
    end

    test "refuses an identity whose device is soft deleted", %{device: device} do
      # The safety net for the case the previous test rules out. An identity is
      # not supposed to outlive its device, but the join checks deleted_at
      # anyway: if a row ever did survive — a soft delete by some path that does
      # not clear identities — resolving it would admit a removed device.
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "abc123"})

      device |> Repo.soft_delete_changeset() |> Repo.update!()

      assert {:error, :device_deleted} =
               ExternalIdentities.get_device_by_identifier(:iroh, "abc123")
    end

    test "does not match the same key under a different service", %{device: device} do
      # (service, identifier) is unique together, not identifier alone, so the
      # service has to be part of the lookup.
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "abc123"})

      assert {:error, :not_found} =
               ExternalIdentities.get_device_by_identifier(:wireguard, "abc123")
    end

    test "matches exactly, without normalising case", %{device: device} do
      # Case-folding cannot be done generically: iroh hex is case-insensitive in
      # practice, a WireGuard base64 key is not. Reporter and caller agree on a
      # form instead.
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "abc123"})

      assert {:error, :not_found} = ExternalIdentities.get_device_by_identifier(:iroh, "ABC123")
    end

    test "finds each endpoint of a device separately", %{device: device} do
      # A device running an iroh console and an iroh application holds one key
      # per instance, and either may be the one asking to use a relay.
      {:ok, _} =
        ExternalIdentities.report(device.id, "iroh", %{identifier: "console", instance: "console"})

      {:ok, _} =
        ExternalIdentities.report(device.id, "iroh", %{identifier: "app", instance: "app"})

      assert {:ok, %{instance: "console"}} =
               ExternalIdentities.get_device_by_identifier(:iroh, "console")

      assert {:ok, %{instance: "app"}} = ExternalIdentities.get_device_by_identifier(:iroh, "app")
    end

    test "refuses a service NervesHub does not know" do
      assert {:error, :unsupported_service} =
               ExternalIdentities.get_device_by_identifier("zerotier", "abc123")
    end

    test "returns not_found when nothing has been reported" do
      assert {:error, :not_found} = ExternalIdentities.get_device_by_identifier(:iroh, "abc123")
    end
  end

  describe "the schema" do
    test "services/0 lists what can be recorded" do
      assert ExternalIdentity.services() == [:iroh, :netbird, :tailscale, :wireguard]
    end

    test "the device association loads through the standard preload path", %{device: device} do
      {:ok, _} = ExternalIdentities.report(device.id, "iroh", %{identifier: "preloaded"})

      device = Repo.preload(device, :external_identities)

      assert [%ExternalIdentity{identifier: "preloaded"}] = device.external_identities
    end
  end
end
