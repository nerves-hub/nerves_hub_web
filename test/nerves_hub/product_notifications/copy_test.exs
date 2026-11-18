defmodule NervesHub.ProductNotifications.CopyTest do
  use ExUnit.Case, async: true

  alias NervesHub.ProductNotifications.Copy
  alias NervesHub.Products.Notification

  # As a notification reads back from the database, with string keys.
  defp notification(kind, metadata, stored \\ %{}) do
    %Notification{
      kind: kind,
      metadata: Map.new(metadata, fn {key, value} -> {to_string(key), value} end),
      title: stored[:title],
      message: stored[:message]
    }
  end

  describe "card/1 and full/2" do
    test "the card leaves out what the notification is about, and the full copy names it" do
      metadata = %{identifier: "sp-0042", host: "devices.example.com"}

      card = Copy.card(notification(:wrong_websocket_host, metadata))
      full = Copy.full(:wrong_websocket_host, metadata)

      assert card.title == "A device connected to the wrong host."
      assert full.title == card.title
      assert card.message =~ "It connected to the management host instead of devices.example.com"
      refute card.message =~ "sp-0042"
      assert full.message =~ "The device 'sp-0042' connected to the management host"
    end

    test "an integration's card leaves out where it was posting" do
      metadata = %{channel: "fleet-alerts", reason: "the bot was removed from the channel"}

      assert Copy.card(notification(:slack_subscription_disabled, metadata)).message =~
               "stopped posting because the bot was removed from the channel."

      assert Copy.full(:slack_subscription_disabled, metadata).message =~
               "stopped posting to #fleet-alerts because the bot was removed from the channel."
    end

    test "a workflow says whether it failed or is waiting" do
      waiting = %{deployment_group: "Canary", step_number: 2, step: "Approval", reason: "awaiting_approval"}
      failed = %{waiting | reason: "failed"} |> Map.put(:failed_count, 3)

      assert Copy.card(notification(:workflow_halted, waiting)).title ==
               "A deployment workflow is waiting for approval."

      assert %{title: "A deployment workflow stopped after devices failed to update.", message: message} =
               Copy.card(notification(:workflow_halted, failed))

      assert message =~ "Step 2 ('Approval') failed: 3 devices could not take the update."
      refute message =~ "Canary"
      assert Copy.full(:workflow_halted, failed).message =~ "of the workflow for deployment group 'Canary'"
    end

    test "a device import says how it went" do
      assert Copy.card(notification(:device_bulk_create, %{created: 240, failed: 3})).message ==
               "240 devices were added, and 3 could not be. Check the manifest for the ones that failed."

      assert Copy.card(notification(:device_bulk_create, %{created: 1, failed: 0})).message ==
               "1 device was added, along with its certificate."
    end

    test "falls back to what was stored for a notification its copy can't be written for" do
      stored = %{title: "An old title.", message: "An old message about 'sp-0042'."}

      # Raised before webhooks stored the reason they were turned off.
      assert Copy.card(notification(:webhook_disabled, %{webhook_id: 1, host: "example.com"}, stored)) == stored
      # Raised before kinds existed, with a key no kind matches.
      assert Copy.card(notification(nil, %{}, stored)) == stored
    end
  end

  describe "rollup/3" do
    test "writes one card for a kind raised on many devices" do
      latest = notification(:wrong_websocket_host, %{identifier: "sp-0042", host: "devices.example.com"})

      assert Copy.rollup(:wrong_websocket_host, 38, latest) == %{
               title: "38 devices connected to the wrong host.",
               message: "They connected to the management host instead of devices.example.com, and were redirected."
             }
    end

    test "a card of one device is that device's card" do
      latest = notification(:missing_firmware_metadata, %{identifier: "sp-0042"})

      assert Copy.rollup(:missing_firmware_metadata, 1, latest) == Copy.card(latest)
    end
  end

  test "detail/1 says what sets one device's notification apart" do
    assert Copy.detail(notification(:extension_failure, %{identifier: "a", extension: "geo", reason: ":enoent"})) ==
             "geo: :enoent"

    assert Copy.detail(notification(:too_many_metrics, %{identifier: "a", reported: 212, max_keys: 50})) ==
             "212 metrics"

    assert Copy.detail(notification(:wrong_websocket_host, %{identifier: "a", host: "b"})) == nil
  end
end
