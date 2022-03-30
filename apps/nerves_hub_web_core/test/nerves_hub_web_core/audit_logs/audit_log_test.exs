defmodule NervesHubWebCore.AuditLogs.AuditLogTest do
  use NervesHubWebCore.DataCase

  alias NervesHubWebCore.{
    AuditLogs.AuditLog,
    Fixtures
  }

  setup do
    Fixtures.standard_fixture()
  end

  describe "build" do
    test "includes changes if present", %{device: device, user: user} do
      params = %{tags: ["howdy"]}
      al = AuditLog.build(user, device, :update, params)
      assert al.changes == params
    end

    test "adds firmware_uuid for device update messages", %{
      deployment: deployment,
      device: device
    } do
      deployment = Repo.preload(deployment, :firmware)
      al = AuditLog.build(deployment, device, :update, %{send_update_message: true})

      assert al.params.firmware_uuid == deployment.firmware.uuid
    end

    test "can use supplied description", %{device: device, user: user} do
      description = "what just happened?!"
      al = AuditLog.build(user, device, :update, %{log_description: description})
      assert al.description == description
      assert al.params == %{}
    end
  end

  describe "create_description" do
    test "default description for create events", context do
      %{device: device, deployment: deployment, firmware: firmware, org: org, user: user} =
        context

      al1 = AuditLog.build(user, device, :create, %{})
      al2 = AuditLog.build(org, device, :create, %{})
      al3 = AuditLog.build(user, deployment, :create, %{})
      al4 = AuditLog.build(user, firmware, :create, %{})

      assert al1.description == "user #{user.username} created device #{device.identifier}"
      assert al2.description == "org #{org.name} created device #{device.identifier}"
      assert al3.description == "user #{user.username} created deployment #{deployment.name}"
      assert al4.description == "user #{user.username} created firmware #{firmware.uuid}"
    end

    test "default description for deleted events", context do
      %{device: device, deployment: deployment, firmware: firmware, org: org, user: user} =
        context

      al1 = AuditLog.build(user, device, :delete, %{})
      al2 = AuditLog.build(org, device, :delete, %{})
      al3 = AuditLog.build(user, deployment, :delete, %{})
      al4 = AuditLog.build(user, firmware, :delete, %{})

      assert al1.description == "user #{user.username} deleted device #{device.identifier}"
      assert al2.description == "org #{org.name} deleted device #{device.identifier}"
      assert al3.description == "user #{user.username} deleted deployment #{deployment.name}"
      assert al4.description == "user #{user.username} deleted firmware #{firmware.uuid}"
    end

    test "marks updates from user without any changes", %{device: device, user: user} do
      al = AuditLog.build(user, device, :update, %{})

      assert al.description ==
               "user #{user.username} submitted update without changes"
    end

    test "description when user changes one or more fields on resource", context do
      %{device: device, user: user} = context
      one_change = AuditLog.build(user, device, :update, %{tags: ["wat"]})
      two_changes = AuditLog.build(user, device, :update, %{description: "howdy", tags: ["wat"]})

      assert one_change.description ==
               "user #{user.username} changed the tags field"

      assert two_changes.description ==
               "user #{user.username} changed the description and tags fields"
    end

    test "description for health changes", context do
      %{device: device, deployment: deployment, user: user} = context

      al1 = AuditLog.build(user, %{deployment | healthy: false}, :update, %{healthy: true})
      al2 = AuditLog.build(user, %{deployment | healthy: true}, :update, %{healthy: false})
      al3 = AuditLog.build(user, %{device | healthy: false}, :update, %{healthy: true})
      al4 = AuditLog.build(user, %{device | healthy: true}, :update, %{healthy: false})

      assert al1.description ==
               "user #{user.username} marked deployment #{deployment.name} healthy"

      assert al2.description ==
               "user #{user.username} marked deployment #{deployment.name} unhealthy"

      assert al3.description == "user #{user.username} marked device #{device.identifier} healthy"

      assert al4.description ==
               "user #{user.username} marked device #{device.identifier} unhealthy"
    end

    test "description for active changes", context do
      %{deployment: deployment, user: user} = context

      al1 = AuditLog.build(user, %{deployment | is_active: false}, :update, %{is_active: true})
      al2 = AuditLog.build(user, %{deployment | is_active: true}, :update, %{is_active: false})

      assert al1.description ==
               "user #{user.username} marked deployment #{deployment.name} active"

      assert al2.description ==
               "user #{user.username} marked deployment #{deployment.name} inactive"
    end

    test "description for reboot attempts", %{device: device, user: user} do
      al1 = AuditLog.build(user, device, :update, %{reboot: true})
      al2 = AuditLog.build(user, device, :update, %{reboot: false})

      assert al1.description ==
               "user #{user.username} triggered reboot on device #{device.identifier}"

      assert al2.description ==
               "user #{user.username} attempted unauthorized reboot on device #{device.identifier}"
    end

    test "description for device updates", context do
      %{deployment: deployment, device: device, firmware: firmware} = context

      al1 =
        AuditLog.build(deployment, device, :update, %{
          send_update_message: true,
          from: "broadcast"
        })

      al2 =
        AuditLog.build(deployment, device, :update, %{
          send_update_message: true,
          from: "channel_join"
        })

      al3 =
        AuditLog.build(deployment, device, :update, %{
          send_update_message: true,
          from: "http_join"
        })

      assert al1.description ==
               "deployment #{deployment.name} update triggered device #{device.identifier} to update firmware #{firmware.uuid}"

      assert al2.description ==
               "device #{device.identifier} received update for firmware #{firmware.uuid} via deployment #{deployment.name} after channel_join"

      assert al3.description ==
               "device #{device.identifier} received update for firmware #{firmware.uuid} via deployment #{deployment.name} after http_join"
    end

    test "description for deployment failures", context do
      %{deployment: deployment, firmware: firmware} = context

      # Deployment failure threshold and rate
      al1 =
        AuditLog.build(deployment, deployment, :update, %{
          healthy: false,
          reason: "failure threshold met"
        })

      al2 =
        AuditLog.build(deployment, deployment, :update, %{
          healthy: false,
          reason: "failure rate met"
        })

      assert al1.description ==
               "deployment #{deployment.name} marked unhealthy. Failure threshold met for firmware #{firmware.uuid}"

      assert al2.description ==
               "deployment #{deployment.name} marked unhealthy. Failure rate met for firmware #{firmware.uuid}"
    end

    test "description for device failures", context do
      %{deployment: deployment, device: device, firmware: firmware} = context

      # Device failure threshold and rate
      al1 =
        AuditLog.build(deployment, device, :update, %{
          healthy: false,
          reason: "device failure threshold met"
        })

      al2 =
        AuditLog.build(deployment, device, :update, %{
          healthy: false,
          reason: "device failure rate met"
        })

      assert al1.description ==
               "device #{device.identifier} marked unhealthy. Device failure threshold met for firmware #{firmware.uuid} in deployment #{deployment.name}"

      assert al2.description ==
               "device #{device.identifier} marked unhealthy. Device failure rate met for firmware #{firmware.uuid} in deployment #{deployment.name}"
    end

    test "default description when unmatched or unknown", %{
      device: device,
      deployment: deployment
    } do
      al = AuditLog.build(deployment, device, :update, %{wat: 1})

      assert al.description ==
               "deployment #{deployment.name} performed unknown update on device #{device.identifier}"
    end
  end
end
