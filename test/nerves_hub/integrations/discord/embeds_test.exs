defmodule NervesHub.Integrations.Discord.EmbedsTest do
  use ExUnit.Case, async: true

  alias NervesHub.Integrations.Discord.Embeds

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

  defp url(path), do: NervesHubWeb.Endpoint.url() <> path

  test "every message is posted under the instance's name, and mentions nobody" do
    message = Embeds.test("acme", "Alice", ["Update failed"])

    assert %{username: "NervesHub", allowed_mentions: %{parse: []}, embeds: [embed]} = message

    assert embed.description ==
             "👋 NervesHub will post Update failed for acme here. This test was sent by Alice."
  end

  test "a health change is titled with what happened, and links to the device" do
    message =
      Embeds.build("device.health_status_changed", [
        device_event("nh-1", %{
          "status" => "unhealthy",
          "previous_status" => "healthy",
          "reasons" => %{"unhealthy" => %{"cpu_usage_percent" => %{"threshold" => 90.0}}}
        })
      ])

    assert %{embeds: [embed]} = message
    assert embed.title == "🔴 nh-1 is now unhealthy"
    assert embed.url == url("/org/acme/thermostat/devices/nh-1")
    assert embed.description == "Was healthy.\ncpu\\_usage\\_percent (threshold 90.0)"
    assert embed.footer == %{text: "thermostat"}
  end

  test "a burst is one embed listing the first ten devices, each linked" do
    events = for n <- 1..12, do: device_event("nh-#{n}", %{"status" => "warning", "previous_status" => "healthy"})

    assert %{embeds: [embed]} = Embeds.build("device.health_status_changed", events)
    assert embed.title == "12 devices changed health status: 12 warning"
    assert embed.description =~ "• 🟡 [nh-1](#{url("/org/acme/thermostat/devices/nh-1")}) warning, was healthy"
    assert embed.description =~ "\nand 2 more"
  end

  test "a workflow waiting for approval links to its deployment group" do
    message =
      Embeds.build("deployment_group.workflow_step.awaiting_approval", [
        %{
          "org" => %{"name" => "acme"},
          "product" => %{"name" => "thermostat"},
          "deployment_group" => %{"name" => "production"},
          "release" => %{"number" => 4, "firmware" => %{"version" => "1.2.0"}},
          "workflow" => %{"steps" => 3},
          "step" => %{"number" => 2, "name" => "Sign-off"}
        }
      ])

    assert %{embeds: [embed]} = message
    assert embed.title == "✋ production is waiting for approval at Sign-off (step 2 of 3)"
    assert embed.url == url("/org/acme/thermostat/deployment_groups/production")
    assert embed.footer == %{text: "thermostat · release 4, firmware 1.2.0"}
  end

  test "more workflow steps than are shown are counted" do
    events =
      for n <- 1..7 do
        %{"deployment_group" => %{"name" => "group-#{n}"}, "step" => %{"number" => 1, "name" => "Canary"}}
      end

    assert %{embeds: embeds} = Embeds.build("deployment_group.workflow_step.failed", events)
    assert length(embeds) == 6
    assert List.last(embeds).description == "And 2 more on the deployment groups' pages."
  end

  test "a product notification links to the product's notifications" do
    message =
      Embeds.build("product.notification_created", [
        %{
          "org" => %{"name" => "acme"},
          "product" => %{"name" => "thermostat"},
          "notification" => %{
            "title" => "A webhook was turned off.",
            "message" => "It kept failing.",
            "level" => "error"
          }
        }
      ])

    assert %{embeds: [embed]} = message
    assert embed.title == "🔴 A webhook was turned off."
    assert embed.description == "It kept failing."
    assert embed.url == url("/org/acme/thermostat/notifications")
  end

  # Masked links and formatting in what a device sent would otherwise render,
  # and could point a reader anywhere.
  test "escapes Discord's markdown in what a device sent" do
    message =
      Embeds.build("device.firmware_update.failed", [
        device_event("nh-1", %{"reason" => "**urgent** [here](https://evil.example.com)\n- step one"})
      ])

    assert %{embeds: [embed]} = message
    assert embed.description == "\\*\\*urgent\\*\\* \\[here\\](https://evil.example.com)\n\\- step one"
  end
end
