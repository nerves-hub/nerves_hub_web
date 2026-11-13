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
      %{type: "actions"} -> []
    end)
  end

  defp buttons(%{blocks: blocks}) do
    for %{type: "actions", elements: elements} <- blocks, button <- elements, do: button
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

  describe "buttons" do
    test "a message about one device can open it, identify it, or reboot it after a confirmation" do
      message =
        Messages.build("device.health_status_changed", [
          device_event("nh-1", %{"status" => "warning", "previous_status" => "healthy"})
        ])

      assert [open, identify, reboot] = buttons(message)
      assert open.url == "#{NervesHubWeb.Endpoint.url()}/org/acme/thermostat/devices/nh-1"
      assert %{action_id: "device.identify", value: "nh-1"} = identify

      assert %{action_id: "device.reboot", value: "nh-1", style: "danger", confirm: %{title: %{text: "Reboot nh-1?"}}} =
               reboot
    end

    test "a summary of many devices has none" do
      events = for n <- 1..2, do: device_event("nh-#{n}", %{"status" => "warning", "previous_status" => "healthy"})

      assert buttons(Messages.build("device.health_status_changed", events)) == []
    end

    test "a success has none" do
      message =
        Messages.build("device.firmware_update.succeeded", [
          device_event("nh-1", %{"outcome" => "succeeded", "target_firmware" => %{"version" => "2.0"}})
        ])

      assert buttons(message) == []
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

    test "a reopened error says so" do
      assert [section | _] = texts(Messages.build("error_group.reopened", [error_event("boom", 7)]))
      assert section =~ "Error reopened in *thermostat*"
    end

    test "several are listed, each linking to its error" do
      message = Messages.build("error_group.created", [error_event("first", 1), error_event("second", 2)])

      assert message.text == "2 new errors"
      assert [_summary, list, _products] = texts(message)
      assert list =~ "/errors/1|first>"
      assert list =~ "/errors/2|second>"
    end
  end

  describe "deployment workflows" do
    defp step_event(step, data \\ %{}) do
      Map.merge(
        %{
          "org" => %{"name" => "acme"},
          "product" => %{"name" => "thermostat"},
          "deployment_group" => %{"name" => "production"},
          "release" => %{"number" => 4, "firmware" => %{"uuid" => "u", "version" => "1.2.0"}},
          "workflow" => %{"steps" => 3},
          "step" => Map.merge(%{"id" => 42, "number" => 1, "name" => "Canary"}, step),
          "user" => nil,
          "failed_devices" => nil
        },
        data
      )
    end

    defp group_url(), do: NervesHubWeb.Endpoint.url() <> "/org/acme/thermostat/deployment_groups/production"

    test "a step starting names the step, where it is in the workflow, and links to the deployment group" do
      message = Messages.build("deployment_group.workflow_step.started", [step_event(%{})])

      assert message.text == "Canary (step 1 of 3) started for production"

      assert [
               ":arrow_forward: *Canary* (step 1 of 3) started for <#{group_url()}|production>",
               "thermostat",
               "release 4, firmware 1.2.0"
             ] == texts(message)

      assert buttons(message) == []
    end

    test "says who retried, approved or skipped a step" do
      alice = %{"user" => %{"name" => "Alice"}}

      assert Messages.build("deployment_group.workflow_step.started", [step_event(%{}, alice)]).text ==
               "Alice retried Canary (step 1 of 3) for production"

      assert Messages.build("deployment_group.workflow_step.completed", [step_event(%{"number" => 2}, alice)]).text ==
               "Alice approved Canary (step 2 of 3) for production"

      assert Messages.build("deployment_group.workflow_step.completed", [step_event(%{})]).text ==
               "Canary (step 1 of 3) completed for production"

      assert Messages.build("deployment_group.workflow_step.skipped", [step_event(%{}, alice)]).text ==
               "Alice skipped Canary (step 1 of 3) for production"
    end

    test "a workflow waiting for approval can be approved, after a confirmation" do
      message =
        Messages.build("deployment_group.workflow_step.awaiting_approval", [
          step_event(%{"number" => 2, "name" => "Sign-off"})
        ])

      assert message.text == "production is waiting for approval at Sign-off (step 2 of 3)"

      assert [approve, open] = buttons(message)
      assert %{action_id: "workflow_step.approve", value: "42", style: "primary"} = approve
      assert approve.confirm.title.text == "Approve Sign-off?"
      assert open.action_id == "deployment_group.open"
      assert open.url == group_url()
    end

    test "a failed step says how many devices failed, and can be retried or skipped" do
      message = Messages.build("deployment_group.workflow_step.failed", [step_event(%{}, %{"failed_devices" => 3})])

      assert message.text ==
               "Canary (step 1 of 3) failed for production: 3 devices could not take the update. The rollout is stopped until the step is retried or skipped."

      assert [
               %{action_id: "workflow_step.retry", value: "42"},
               %{action_id: "workflow_step.skip", value: "42", style: "danger", confirm: %{}},
               %{action_id: "deployment_group.open"}
             ] = buttons(message)
    end

    test "a step dealt with has a line saying so in place of its buttons" do
      events = [step_event(%{}), step_event(%{"id" => 43, "name" => "Second"})]

      message =
        Messages.build("deployment_group.workflow_step.awaiting_approval", events, %{
          "42" => %{"change" => "replaced", "release" => 5}
        })

      assert ":leftwards_arrow_with_hook: Release 5 replaced this one, so there is nothing more to do here" in texts(
               message
             )

      assert [%{action_id: "workflow_step.approve", value: "43"}, %{action_id: "deployment_group.open"}] =
               buttons(message)
    end

    test "several are each given their own section and buttons" do
      events = for id <- 1..7, do: step_event(%{"id" => id}, %{"deployment_group" => %{"name" => "group-#{id}"}})
      message = Messages.build("deployment_group.workflow_step.failed", events)

      assert message.text == "7 workflow steps failed"
      assert length(buttons(message)) == 15
      assert "And 2 more on the deployment groups' pages." in texts(message)
    end

    test "escapes the names people gave steps and deployment groups" do
      message =
        Messages.build("deployment_group.workflow_step.started", [
          step_event(%{"name" => "<!channel>"}, %{"deployment_group" => %{"name" => "<https://evil.example.com|x>"}})
        ])

      refute Enum.any?(texts(message), &(&1 =~ "<!channel>"))
      refute message.text =~ "<https://evil"
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
