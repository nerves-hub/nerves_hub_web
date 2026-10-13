defmodule NervesHubWeb.Integrations.Slack.ActionsTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Connections
  alias NervesHub.Fixtures
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.ScriptResults
  alias NervesHub.Integrations.Slack.UserLink
  alias NervesHubWeb.Integrations.Slack.Actions
  alias Phoenix.Socket.Broadcast

  @moduletag :tmp_dir

  @response_url "https://hooks.slack.com/actions/T0ACME/1/abc"

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
    :ok = Connections.device_connected(connection.id)

    _slack = Fixtures.slack_connection_fixture(org, user, %{team_id: "T0ACME"})

    test_pid = self()

    Req.Test.stub(Slack, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:slack, conn.host, conn.request_path, body})

      case conn.host do
        "hooks.slack.com" -> Plug.Conn.send_resp(conn, 200, "ok")
        _api -> Req.Test.json(conn, %{"ok" => true})
      end
    end)

    %{connection_id: connection.id, device: device, org: org, user: user}
  end

  defp link!(user, slack_user_id \\ "U0ALICE", team_id \\ "T0ACME") do
    _link =
      NervesHub.Repo.insert!(%UserLink{
        user_id: user.id,
        team_id: team_id,
        slack_user_id: slack_user_id,
        slack_name: "Alice",
        linked_at: DateTime.utc_now()
      })

    :ok
  end

  defp click(device, action_id, overrides \\ %{}) do
    Map.merge(
      %{
        action_id: action_id,
        identifier: device.identifier,
        team_id: "T0ACME",
        slack_user_id: "U0ALICE",
        slack_username: "alice",
        response_url: @response_url,
        channel_id: "C0FLEET",
        message_ts: "1728900000.000100"
      },
      overrides
    )
  end

  defp private_reply() do
    assert_received {:slack, "hooks.slack.com", "/actions/T0ACME/1/abc", body}
    body = Jason.decode!(body)
    assert %{"response_type" => "ephemeral", "replace_original" => false} = body
    body
  end

  describe "perform/1" do
    test "reboots the device as the linked user, and says so in the thread", %{device: device, user: user} do
      :ok = link!(user)
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

      assert {:ok, "device.reboot"} = Actions.perform(click(device, "device.reboot"))

      assert_receive %Broadcast{event: "reboot"}

      assert [log | _] = AuditLogs.logs_for(device)

      assert log.description ==
               "User #{user.name} rebooted device #{device.identifier} from Slack user U0ALICE (@alice, workspace T0ACME)"

      assert log.actor_id == user.id

      assert_received {:slack, "slack.com", "/api/chat.postMessage", body}

      assert %{"channel" => "C0FLEET", "thread_ts" => "1728900000.000100", "text" => text} = Jason.decode!(body)
      assert text =~ "#{user.name} rebooted *#{device.identifier}* from Slack."
    end

    test "does not reboot a device asked to reboot a moment ago, and says by whom", %{device: device, user: user} do
      :ok = link!(user)
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

      assert {:ok, "device.reboot"} = Actions.perform(click(device, "device.reboot"))

      assert {:error, :just_rebooted} =
               Actions.perform(click(device, "device.reboot", %{slack_user_id: "U0ALICE"}))

      assert_receive %Broadcast{event: "reboot"}
      refute_receive %Broadcast{event: "reboot"}, 100

      assert %{"text" => text} = private_reply()

      assert text ==
               "#{device.identifier} was asked to reboot by #{user.name} less than a minute ago, so NervesHub did not ask again."
    end

    test "identifying twice in a row is fine", %{device: device, user: user} do
      :ok = link!(user)

      assert {:ok, "device.identify"} = Actions.perform(click(device, "device.identify"))
      assert {:ok, "device.identify"} = Actions.perform(click(device, "device.identify"))
    end

    test "asks the device to identify itself", %{device: device, user: user} do
      :ok = link!(user)
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

      assert {:ok, "device.identify"} = Actions.perform(click(device, "device.identify"))

      assert_receive %Broadcast{event: "identify"}
      assert [log | _] = AuditLogs.logs_for(device)
      assert log.description =~ "identify itself from Slack"
    end

    test "asks a Slack user who is not linked to link, privately", %{device: device} do
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

      assert {:error, :not_linked} = Actions.perform(click(device, "device.reboot"))

      refute_receive %Broadcast{event: "reboot"}
      assert %{"blocks" => blocks} = private_reply()

      assert [%{"elements" => [%{"url" => url}]}] = Enum.filter(blocks, &(&1["type"] == "actions"))
      assert url == "#{NervesHubWeb.Endpoint.url()}/integrations/slack/link?team=T0ACME"
    end

    test "refuses a member whose role cannot reboot", %{device: device, org: org} do
      viewer = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, viewer, %{role: :view})
      :ok = link!(viewer)

      assert {:error, :not_allowed} = Actions.perform(click(device, "device.reboot"))
      assert %{"text" => "Your role in NervesHub does not let you ask a device to reboot."} = private_reply()
    end

    test "refuses somebody who is not a member of the device's organization", %{device: device} do
      :ok = link!(Fixtures.user_fixture())

      assert {:error, :not_member} = Actions.perform(click(device, "device.reboot"))
      assert %{"text" => "Your NervesHub account is not a member of the organization" <> _} = private_reply()
    end

    test "refuses a click from a workspace the device's organization is not connected to", %{device: device, user: user} do
      Fixtures.slack_connection_fixture(Fixtures.org_fixture(user, %{name: "elsewhere"}), user, %{team_id: "T0OTHER"})

      :ok = link!(user, "U0ALICE", "T0OTHER")

      assert {:error, :not_connected} = Actions.perform(click(device, "device.reboot", %{team_id: "T0OTHER"}))
    end

    test "refuses an offline device", %{connection_id: connection_id, device: device, user: user} do
      :ok = link!(user)
      :ok = Connections.device_disconnected(connection_id, "a test")

      assert {:error, :offline} = Actions.perform(click(device, "device.reboot"))
      assert %{"text" => text} = private_reply()
      assert text =~ "is offline"
    end

    test "refuses a device that is gone", %{device: device, user: user} do
      :ok = link!(user)
      {:ok, _} = NervesHub.Devices.delete_device(device)

      assert {:error, :no_device} = Actions.perform(click(device, "device.reboot"))
    end

    test "escapes the identifier it was given in what it says", %{device: device, user: user} do
      :ok = link!(user)

      assert {:error, :no_device} =
               Actions.perform(click(device, "device.reboot", %{identifier: "<https://evil.example.com|Link>"}))

      assert %{"text" => text} = private_reply()
      refute text =~ "<https://evil"
      assert text =~ "&lt;https://evil.example.com|Link&gt;"
    end

    test "only answers through Slack's own response URLs", %{device: device} do
      assert {:error, :not_linked} =
               Actions.perform(click(device, "device.reboot", %{response_url: "https://evil.example.com/hook"}))

      refute_received {:slack, _, _, _}
    end
  end

  describe "handle_interaction/1" do
    test "carries out a button click in the background", %{device: device, user: user} do
      :ok = link!(user)

      payload = %{
        "type" => "block_actions",
        "team" => %{"id" => "T0ACME"},
        "user" => %{"id" => "U0ALICE", "username" => "alice"},
        "response_url" => @response_url,
        "container" => %{"channel_id" => "C0FLEET", "message_ts" => "1728900000.000100"},
        "actions" => [%{"action_id" => "device.reboot", "value" => device.identifier}]
      }

      assert :ok = Actions.handle_interaction(payload)
      assert_receive {:slack, "slack.com", "/api/chat.postMessage", _body}, 2000
    end

    test "acts on a request once, however often it is replayed", %{device: device, user: user} do
      :ok = link!(user)
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

      payload = %{
        "type" => "block_actions",
        "trigger_id" => "1728900000.1.abc",
        "team" => %{"id" => "T0ACME"},
        "user" => %{"id" => "U0ALICE", "username" => "alice"},
        "response_url" => @response_url,
        "actions" => [%{"action_id" => "device.identify", "value" => device.identifier}]
      }

      assert :ok = Actions.handle_interaction(payload)
      assert :ok = Actions.handle_interaction(payload)

      assert_receive %Broadcast{event: "identify"}, 2000
      refute_receive %Broadcast{event: "identify"}, 300
    end

    test "shares a script's output when its Share button is clicked", %{device: device, user: user} do
      :ok = link!(user)

      id =
        ScriptResults.store(%{
          user_id: user.id,
          team_id: "T0ACME",
          slack_user_id: "U0ALICE",
          device_identifier: device.identifier,
          script_name: "uptime",
          output: "up 3 days"
        })

      payload = %{
        "type" => "block_actions",
        "team" => %{"id" => "T0ACME"},
        "user" => %{"id" => "U0ALICE"},
        "response_url" => @response_url,
        "actions" => [%{"action_id" => "script.share", "value" => id}]
      }

      assert :ok = Actions.handle_interaction(payload)
      assert_receive {:slack, "hooks.slack.com", _path, body}, 2000
      assert %{"response_type" => "in_channel"} = Jason.decode!(body)
    end

    test "ignores link buttons and anything else Slack sends", %{device: device} do
      assert :ok =
               Actions.handle_interaction(%{
                 "type" => "block_actions",
                 "team" => %{"id" => "T0ACME"},
                 "user" => %{"id" => "U0ALICE"},
                 "actions" => [
                   %{"action_id" => "device.open", "value" => device.identifier},
                   %{"action_id" => "account.link"}
                 ]
               })

      assert :ok = Actions.handle_interaction(%{"type" => "view_submission"})
      refute_receive {:slack, _, _, _}, 200
    end
  end
end
