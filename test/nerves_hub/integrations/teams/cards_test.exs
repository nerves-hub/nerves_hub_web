defmodule NervesHub.Integrations.Teams.CardsTest do
  use ExUnit.Case, async: true

  alias NervesHub.Integrations.Teams.Cards

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

  defp card(%{"type" => "message", "attachments" => [attachment]}) do
    assert %{"contentType" => "application/vnd.microsoft.card.adaptive", "content" => card} = attachment
    assert %{type: "AdaptiveCard", version: "1.4"} = card
    card
  end

  # Each line of the card, as Teams would show it.
  defp lines(message) do
    for %{type: "RichTextBlock", inlines: inlines} <- card(message).body, do: Enum.map_join(inlines, & &1.text)
  end

  defp runs(message), do: for(%{inlines: inlines} <- card(message).body, run <- inlines, do: run)

  defp actions(message), do: Map.get(card(message), :actions, [])

  defp url(path), do: NervesHubWeb.Endpoint.url() <> path

  test "a health change names the device, links to it, and gives the reasons" do
    message =
      Cards.build("device.health_status_changed", [
        device_event("nh-1", %{
          "status" => "unhealthy",
          "previous_status" => "healthy",
          "reasons" => %{"unhealthy" => %{"cpu_usage_percent" => %{"threshold" => 90.0}}}
        })
      ])

    assert ["🔴 nh-1 is now unhealthy, was healthy", "thermostat · cpu_usage_percent (threshold 90.0)"] = lines(message)

    assert %{selectAction: %{type: "Action.OpenUrl", url: device_url}} = Enum.find(runs(message), &(&1.text == "nh-1"))
    assert device_url == url("/org/acme/thermostat/devices/nh-1")

    assert [%{type: "Action.OpenUrl", title: "Open in NervesHub", url: ^device_url}] = actions(message)
  end

  test "a burst is summarized, listing the first ten devices" do
    events = for n <- 1..12, do: device_event("nh-#{n}", %{"status" => "warning", "previous_status" => "healthy"})
    message = Cards.build("device.health_status_changed", events)

    assert ["12 devices changed health status: 12 warning" | rest] = lines(message)
    assert "• 🟡 nh-1 warning, was healthy" in rest
    assert "and 2 more" in rest
    assert actions(message) == []
  end

  test "an update failure says how it failed, and why" do
    message =
      Cards.build("device.firmware_update.failed", [
        device_event("nh-1", %{
          "outcome" => "expired",
          "reason" => "no progress for 15 minutes",
          "target_firmware" => %{"version" => "2.0.0"},
          "source_firmware" => %{"version" => "1.9.0"},
          "deployment_group" => %{"name" => "production"}
        })
      ])

    assert [
             "❌ Update to 2.0.0 stopped reporting progress on nh-1: no progress for 15 minutes",
             "thermostat · deployment group production · from 1.9.0"
           ] = lines(message)
  end

  test "a new error links to it" do
    message =
      Cards.build("error_group.created", [
        %{
          "org" => %{"name" => "acme"},
          "product" => %{"name" => "thermostat"},
          "error" => %{"id" => 7, "reason" => "** (RuntimeError) boom", "top_frame" => "MyApp.run/0"}
        }
      ])

    assert ["🚨 New error in thermostat: ** (RuntimeError) boom", "MyApp.run/0"] = lines(message)
    assert [%{title: "View the error", url: error_url}] = actions(message)
    assert error_url == url("/org/acme/thermostat/errors/7")
  end

  test "a workflow waiting for approval links to its deployment group, which is where it is approved" do
    message =
      Cards.build("deployment_group.workflow_step.awaiting_approval", [
        %{
          "org" => %{"name" => "acme"},
          "product" => %{"name" => "thermostat"},
          "deployment_group" => %{"name" => "production"},
          "release" => %{"number" => 4, "firmware" => %{"version" => "1.2.0"}},
          "workflow" => %{"steps" => 3},
          "step" => %{"id" => 42, "number" => 2, "name" => "Sign-off"}
        }
      ])

    assert ["✋ production is waiting for approval at Sign-off (step 2 of 3)", "thermostat · release 4, firmware 1.2.0"] =
             lines(message)

    assert [%{title: "Open in NervesHub", url: group_url}] = actions(message)
    assert group_url == url("/org/acme/thermostat/deployment_groups/production")
  end

  test "a product notification carries its title, message and a link to the product's notifications" do
    message =
      Cards.build("product.notification_created", [
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

    assert ["🔴 A webhook was turned off.", "It kept failing.", "thermostat · Notifications"] = lines(message)
    assert %{selectAction: %{url: notifications_url}} = Enum.find(runs(message), &(&1.text == "Notifications"))
    assert notifications_url == url("/org/acme/thermostat/notifications")
  end

  # Teams renders markdown in a TextBlock but not in a TextRun, which is why
  # text from devices goes only in runs.
  test "what a device sent is plain text in a run, never markdown" do
    message =
      Cards.build("device.firmware_update.failed", [
        device_event("[click me](https://evil.example.com)", %{
          "reason" => "**urgent** [here](https://evil.example.com)"
        })
      ])

    for element <- card(message).body, do: assert(element.type == "RichTextBlock")
    assert Enum.all?(runs(message), &(&1.type == "TextRun"))
    assert Enum.any?(runs(message), &(&1.text =~ "**urgent** [here](https://evil.example.com)"))

    for %{selectAction: %{url: link}} <- runs(message),
        do: assert(String.starts_with?(link, NervesHubWeb.Endpoint.url()))
  end

  test "the test message says what the channel will get, and who sent it" do
    assert [text] = lines(Cards.test("acme", "Alice", ["Update failed", "New error"]))
    assert text == "👋 NervesHub will post Update failed, New error for acme here. This test was sent by Alice."
  end
end
