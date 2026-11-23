defmodule NervesHub.AuditLogs.TemplateTest do
  use ExUnit.Case, async: true

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.Template
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.ApiKey
  alias NervesHub.Products.Product

  doctest Template

  @user %User{id: 1, name: "Jeff"}
  @device %Device{id: 2, identifier: "abc123", org_id: 3}

  describe "new/2" do
    test "needs no values for the actor and resource" do
      assert %Template{values: %{}} = Template.new("%{actor} rebooted device %{resource}")
    end

    test "raises for a placeholder with no value" do
      assert_raise ArgumentError, ~r/no value for %\{script\}/, fn ->
        Template.new("%{actor} ran support script %{script}")
      end
    end
  end

  describe "dump_values/3" do
    test "stores the actor and resource as references, under their names now" do
      values = "%{actor} rebooted device %{resource}" |> Template.new() |> Template.dump_values(@user, @device)

      assert values == %{
               "actor" => %{"type" => "user", "id" => 1, "name" => "Jeff"},
               "resource" => %{"type" => "device", "id" => 2, "name" => "abc123"}
             }
    end

    test "names an API key actor as one" do
      values =
        "%{actor} rebooted device %{resource}"
        |> Template.new()
        |> Template.dump_values(%ApiKey{id: 5, name: "ci"}, @device)

      assert values["actor"] == %{"type" => "api_key", "id" => 5, "name" => "API key ci"}
    end

    test "stores a product as a reference under its name" do
      values =
        "%{actor} moved %{device}"
        |> Template.new(device: @device)
        |> Template.dump_values(@user, %Product{id: 6, name: "Hop"})

      assert values["resource"] == %{"type" => "product", "id" => 6, "name" => "Hop"}
      assert values["device"] == %{"type" => "device", "id" => 2, "name" => "abc123"}
    end

    test "stores an organization as a reference under its name" do
      values = "%{actor} %{resource}" |> Template.new() |> Template.dump_values(@user, %Org{id: 7, name: "Acme"})

      assert values["resource"] == %{"type" => "org", "id" => 7, "name" => "Acme"}
    end

    test "stores firmware and archives by UUID, and text and numbers as text" do
      group = %DeploymentGroup{id: 4, name: "Canary"}

      values =
        "%{firmware} %{group} %{minutes} %{reason}"
        |> Template.new(
          firmware: %FirmwareMetadata{uuid: "f-uuid", version: "1.0.0"},
          group: group,
          minutes: 60,
          reason: nil
        )
        |> Template.dump_values(group, @device)

      assert values["firmware"] == %{"type" => "firmware", "id" => "f-uuid", "name" => "f-uuid"}
      assert values["group"] == %{"type" => "deployment_group", "id" => 4, "name" => "Canary"}
      assert values["minutes"] == "60"
      assert values["reason"] == ""
    end

    test "takes firmware metadata as the plain map a device holds after an update" do
      metadata = %{uuid: "f-uuid", version: "1.0.0", product: "Hop"}

      values = "%{firmware}" |> Template.new(firmware: metadata) |> Template.dump_values(@user, @device)

      assert values["firmware"] == %{"type" => "firmware", "id" => "f-uuid", "name" => "f-uuid"}
    end
  end

  describe "to_text/2" do
    test "fills each placeholder with its text, or a reference's stored name" do
      values = %{"actor" => %{"type" => "user", "id" => 1, "name" => "Jeff"}, "via" => "Slack"}

      assert Template.to_text("%{actor} rebooted it from %{via}", values) == "Jeff rebooted it from Slack"
    end

    test "never reads placeholders out of a value" do
      values = %{"actor" => %{"type" => "user", "id" => 1, "name" => "Jeff"}, "reason" => "%{actor}"}

      assert Template.to_text("Failed: %{reason}", values) == "Failed: %{actor}"
    end

    test "leaves a placeholder with no stored value as written" do
      assert Template.to_text("Sent %{archive}", %{}) == "Sent %{archive}"
    end
  end

  describe "reference_keys/1" do
    test "lists the references, not the text" do
      values = %{
        "actor" => %{"type" => "user", "id" => 1, "name" => "Jeff"},
        "firmware" => %{"type" => "firmware", "id" => "f-uuid", "name" => "f-uuid"},
        "reason" => "out of space"
      }

      assert Enum.sort(Template.reference_keys(values)) == [{"firmware", "f-uuid"}, {"user", 1}]
    end

    test "an entry written without a template has none" do
      assert Template.reference_keys(nil) == []
    end
  end
end
