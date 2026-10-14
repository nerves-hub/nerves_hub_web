defmodule NervesHub.Integrations.Slack.MessagesTest do
  use ExUnit.Case, async: true

  alias NervesHub.Integrations.Slack.Messages

  defp device_event(identifier, data) do
    Map.merge(
      %{
        "org" => %{"name" => "acme"},
        "product" => %{"name" => "thermostat"},
        "device" => %{"identifier" => identifier}
      },
      data
    )
  end

  defp texts(%{blocks: blocks}) do
    Enum.flat_map(blocks, fn
      %{type: "section", text: %{text: text}} -> [text]
      %{type: "context", elements: elements} -> Enum.map(elements, & &1.text)
    end)
  end

  describe "health status changes" do
    test "one change names the device, links to it, and gives the reasons" do
      message =
        Messages.build("device.health_status_changed", [
          device_event("nh-1", %{
            "status" => "unhealthy",
            "previous_status" => "healthy",
            "reasons" => %{"unhealthy" => %{"cpu_usage_percent" => %{"threshold" => 90.0}}, "warning" => %{}}
          })
        ])

      assert message.text == "nh-1 is now unhealthy, was healthy"

      assert [section, "thermostat", "cpu_usage_percent (threshold 90.0)"] = texts(message)
      assert section =~ ":red_circle:"
      assert section =~ "<#{NervesHubWeb.Endpoint.url()}/org/acme/thermostat/devices/nh-1|nh-1>"
    end

    test "a burst is summarized, listing each device once, as it ended" do
      events =
        [
          device_event("nh-1", %{"status" => "warning", "previous_status" => "healthy"}),
          device_event("nh-1", %{"status" => "unhealthy", "previous_status" => "warning"})
        ] ++
          for(n <- 2..13, do: device_event("nh-#{n}", %{"status" => "warning", "previous_status" => "healthy"}))

      message = Messages.build("device.health_status_changed", events)

      assert message.text == "13 devices changed health status: 1 unhealthy, 12 warning"

      [_summary, list | _] = texts(message)
      assert list =~ "nh-1|nh-1> unhealthy, was healthy"
      assert list =~ "and 3 more"
      refute list =~ "nh-13"
    end
  end

  describe "updates" do
    test "a failure says how it failed, and why" do
      message =
        Messages.build("device.firmware_update.failed", [
          device_event("nh-1", %{
            "outcome" => "expired",
            "reason" => "watchdog",
            "target_firmware" => %{"version" => "1.4.2"},
            "source_firmware" => %{"version" => "1.4.1"},
            "deployment_group" => %{"name" => "production"}
          })
        ])

      assert message.text == "Update to 1.4.2 stopped reporting progress on nh-1"
      assert [section, "thermostat", "deployment group production", "from 1.4.1"] = texts(message)
      assert section =~ "stopped reporting progress"
      assert section =~ ": watchdog"
    end

    test "successes are counted by the version they reached" do
      events =
        for(
          n <- 1..3,
          do: device_event("nh-#{n}", %{"outcome" => "succeeded", "target_firmware" => %{"version" => "2.0"}})
        ) ++
          [device_event("nh-4", %{"outcome" => "succeeded", "target_firmware" => %{"version" => "1.9"}})]

      assert %{text: "4 devices updated: 3 to 2.0, 1 to 1.9"} =
               Messages.build("device.firmware_update.succeeded", events)
    end
  end

  describe "errors" do
    defp error_event(reason, id) do
      %{
        "org" => %{"name" => "acme"},
        "product" => %{"name" => "thermostat"},
        "error" => %{"id" => id, "reason" => reason, "top_frame" => "MyApp.Worker.handle_info/2 (lib/worker.ex:42)"}
      }
    end

    test "a new error names the product and the reason, and links to the error" do
      message = Messages.build("error_group.created", [error_event("** (RuntimeError) `boom` <!here>", 7)])

      assert [section, frame, link] = texts(message)
      assert section == ":rotating_light: New error in *thermostat*: `** (RuntimeError) 'boom' &lt;!here&gt;`"
      assert frame == "MyApp.Worker.handle_info/2 (lib/worker.ex:42)"
      assert link == "<#{NervesHubWeb.Endpoint.url()}/org/acme/thermostat/errors/7|View the error>"
      refute message.text =~ "<!here>"
    end

    test "a reopened error says it is back" do
      assert [section | _] = texts(Messages.build("error_group.reopened", [error_event("boom", 7)]))
      assert section =~ "A resolved error is back in *thermostat*"
    end

    test "several are listed, each linking to its error" do
      message = Messages.build("error_group.created", [error_event("first", 1), error_event("second", 2)])

      assert message.text == "2 new errors"
      assert [_summary, list, _products] = texts(message)
      assert list =~ "/errors/1|first>"
      assert list =~ "/errors/2|second>"
    end
  end

  test "product notifications carry their title, message and a link to the product's notifications" do
    message =
      Messages.build("product.notification_created", [
        %{
          "org" => %{"name" => "acme"},
          "product" => %{"name" => "thermostat"},
          "notification" => %{"title" => "A webhook was turned off.", "message" => "It failed.", "level" => "error"}
        }
      ])

    assert message.text == "A webhook was turned off."
    assert [section, _product, link] = texts(message)
    assert section == ":red_circle: *A webhook was turned off.*\nIt failed."
    assert link == "<#{NervesHubWeb.Endpoint.url()}/org/acme/thermostat/notifications|Notifications>"
  end

  test "escapes what devices send, so it cannot mention the channel or become a link" do
    message =
      Messages.build("device.firmware_update.failed", [
        device_event("<!channel>", %{
          "outcome" => "failed",
          "reason" => "<https://evil.example.com|click> & run",
          "target_firmware" => %{"version" => "1.0"}
        })
      ])

    text = Enum.join(texts(message), "\n") <> message.text

    refute text =~ "<!channel>"
    refute text =~ "<https://evil.example.com"
    assert text =~ "&lt;!channel&gt;"
    assert text =~ "&lt;https://evil.example.com|click&gt; &amp; run"
  end

  test "cuts long text before escaping it" do
    reason = String.duplicate("a", 299) <> "&b"

    message =
      Messages.build("device.firmware_update.failed", [
        device_event("nh-1", %{"outcome" => "failed", "reason" => reason, "target_firmware" => %{"version" => "1.0"}})
      ])

    [section | _] = texts(message)
    assert section =~ "a&amp;…"
  end
end
