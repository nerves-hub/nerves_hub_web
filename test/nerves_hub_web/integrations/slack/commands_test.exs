defmodule NervesHubWeb.Integrations.Slack.CommandsTest do
  use NervesHub.DataCase, async: false
  use Mimic

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Connections
  alias NervesHub.Fixtures
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.UserLink
  alias NervesHub.Repo
  alias NervesHub.Scripts.Runner
  alias NervesHubWeb.Integrations.Slack.Actions
  alias NervesHubWeb.Integrations.Slack.Commands
  alias NervesHubWeb.Integrations.Slack.DeviceCards
  alias Phoenix.Socket.Broadcast

  @moduletag :tmp_dir

  @response_url "https://hooks.slack.com/commands/T0ACME/1/abc"

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org, %{name: "thermostat"})
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
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    %{connection_id: connection.id, device: device, org: org, product: product, user: user}
  end

  defp link!(user) do
    Repo.insert!(%UserLink{
      user_id: user.id,
      team_id: "T0ACME",
      slack_user_id: "U0ALICE",
      slack_name: "Alice",
      linked_at: DateTime.utc_now()
    })

    :ok
  end

  defp command(text) do
    Commands.handle(%{
      "team_id" => "T0ACME",
      "user_id" => "U0ALICE",
      "user_name" => "alice",
      "command" => "/nerveshub",
      "text" => text,
      "response_url" => @response_url
    })
  end

  test "help, or nothing, lists what the command does" do
    assert %{response_type: "ephemeral", text: text} = command("")
    assert text =~ "`/nerveshub device <identifier>`"

    assert %{response_type: "ephemeral", text: text} = command("explode nh-1")
    assert text =~ "`explode` is not something `/nerveshub` does."
  end

  test "link sends the Slack user to link their account" do
    assert %{response_type: "ephemeral", blocks: blocks} = command("link")
    assert [%{elements: [%{url: url}]}] = Enum.filter(blocks, &(&1.type == "actions"))
    assert url == "#{NervesHubWeb.Endpoint.url()}/integrations/slack/link?team=T0ACME"
  end

  test "asks a Slack user who is not linked to link first", %{device: device} do
    assert %{response_type: "ephemeral", text: "Link your Slack account to NervesHub" <> _} =
             command("device #{device.identifier}")
  end

  describe "device" do
    test "shows the device's state, with its buttons, to the person who asked", %{device: device, user: user} do
      :ok = link!(user)

      assert %{response_type: "ephemeral", blocks: [card, buttons]} = command("device #{device.identifier}")

      fields = Enum.map(card.fields, & &1.text)
      assert "*Connection*\nOnline" in fields
      assert "*Health*\nNot judged yet" in fields
      assert "*Product*\nthermostat" in fields

      assert %{
               type: "actions",
               elements: [
                 %{action_id: "device.open"},
                 %{action_id: "device.identify"},
                 %{action_id: "device.reboot"},
                 %{action_id: "device.share", value: identifier}
               ]
             } = buttons

      assert identifier == device.identifier
    end

    test "says when the device was last seen once it is offline", %{connection_id: id, device: device, user: user} do
      :ok = link!(user)
      :ok = Connections.device_disconnected(id)

      assert %{blocks: [card, _]} = command("device #{device.identifier}")
      assert Enum.any?(card.fields, &(&1.text =~ "Offline, last seen <!date^"))
    end

    test "is refused for a device of an organization this workspace is not connected to", %{user: user} = context do
      :ok = link!(user)
      other_org = Fixtures.org_fixture(user, %{name: "elsewhere"})
      other_product = Fixtures.product_fixture(user, other_org)
      other_key = Fixtures.org_key_fixture(other_org, user, context.tmp_dir)
      other_firmware = Fixtures.firmware_fixture(other_key, other_product, %{dir: context.tmp_dir})
      theirs = Fixtures.device_fixture(other_org, other_product, other_firmware)

      assert %{response_type: "ephemeral", text: "This Slack workspace is not connected" <> _} =
               command("device #{theirs.identifier}")
    end
  end

  describe "sharing a device" do
    defp share(device, slack_user_id \\ "U0ALICE") do
      DeviceCards.share(%{
        identifier: device.identifier,
        team_id: "T0ACME",
        slack_user_id: slack_user_id,
        response_url: @response_url
      })
    end

    test "posts the device's card to the channel, saying who shared it", %{device: device, user: user} do
      :ok = link!(user)

      assert :ok = share(device)

      assert_received {:slack, "hooks.slack.com", _path, body}

      assert %{"response_type" => "in_channel", "replace_original" => false, "blocks" => [card, buttons]} =
               Jason.decode!(body)

      assert card["text"]["text"] == "#{user.name} shared *#{device.identifier}*:"
      refute Enum.any?(buttons["elements"], &(&1["action_id"] == "device.share"))
    end

    test "checks the sharer can still see the device", %{device: device, org: org, user: user} do
      :ok = link!(user)
      {:ok, org_user} = Accounts.get_org_user(org, user)
      :ok = Accounts.soft_delete_org_user(org_user)

      assert {:error, :not_member} = share(device)
      assert_received {:slack, "hooks.slack.com", _path, body}
      assert %{"response_type" => "ephemeral"} = Jason.decode!(body)
    end

    test "a click on the button shares it", %{device: device, user: user} do
      :ok = link!(user)

      :ok =
        Actions.handle_interaction(%{
          "type" => "block_actions",
          "team" => %{"id" => "T0ACME"},
          "user" => %{"id" => "U0ALICE"},
          "response_url" => @response_url,
          "actions" => [%{"action_id" => "device.share", "value" => device.identifier}]
        })

      assert_receive {:slack, "hooks.slack.com", _path, body}, 2000
      assert %{"response_type" => "in_channel"} = Jason.decode!(body)
    end
  end

  test "names the instance as it is configured", %{device: device, user: user} do
    on_exit(fn -> Application.put_env(:nerves_hub, :friendly_platform_name, "NervesHub") end)
    Application.put_env(:nerves_hub, :friendly_platform_name, "NervesCloud")

    assert %{text: text} = command("help")
    assert text =~ "links your NervesCloud account"

    assert %{text: "Link your Slack account to NervesCloud" <> _} = command("device #{device.identifier}")

    :ok = link!(user)
    assert %{blocks: [_card, %{elements: [open | _]}]} = command("device #{device.identifier}")
    assert open.text.text == "Open in NervesCloud"
  end

  describe "reboot and identify" do
    test "reboot tells the channel who did it, and audits it", %{device: device, user: user} do
      :ok = link!(user)
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

      assert %{response_type: "in_channel", text: text} = command("reboot #{device.identifier}")
      assert text =~ "#{user.name} rebooted *#{device.identifier}* from Slack."

      assert_receive %Broadcast{event: "reboot"}
      assert [log | _] = AuditLogs.logs_for(device)
      assert log.description =~ "rebooted device #{device.identifier} from Slack user U0ALICE"
    end

    test "identify asks the device to identify itself", %{device: device, user: user} do
      :ok = link!(user)
      :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

      assert %{response_type: "in_channel"} = command("identify #{device.identifier}")
      assert_receive %Broadcast{event: "identify"}
    end

    test "a reboot right after another is refused, button or command", %{device: device, user: user} do
      :ok = link!(user)

      assert %{response_type: "in_channel"} = command("reboot #{device.identifier}")
      assert %{response_type: "ephemeral", text: text} = command("reboot #{device.identifier}")
      assert text =~ "was asked to reboot by #{user.name} less than a minute ago"
    end

    test "a replayed command is answered once" do
      params = %{"team_id" => "T0ACME", "user_id" => "U0ALICE", "text" => "help", "trigger_id" => "1728.1.xyz"}

      assert %{text: "`/nerveshub device" <> _} = Commands.handle(params)
      assert %{text: "This command was already answered."} = Commands.handle(params)
    end

    test "a viewer cannot reboot", %{device: device, org: org} do
      viewer = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, viewer, %{role: :view})
      :ok = link!(viewer)

      assert %{response_type: "ephemeral", text: "Your role in NervesHub does not let you ask a device to reboot."} =
               command("reboot #{device.identifier}")
    end

    test "an offline device is not asked", %{connection_id: id, device: device, user: user} do
      :ok = link!(user)
      :ok = Connections.device_disconnected(id)

      assert %{response_type: "ephemeral", text: text} = command("reboot #{device.identifier}")
      assert text =~ "is offline"
    end
  end

  describe "script" do
    test "lists the product's scripts", %{device: device, product: product, user: user} do
      :ok = link!(user)
      Fixtures.support_script_fixture(product, user, %{name: "uptime"})
      Fixtures.support_script_fixture(product, user, %{name: "disk usage"})

      assert %{response_type: "ephemeral", text: text} = command("script #{device.identifier}")
      assert text =~ "• `disk usage`\n• `uptime`"
    end

    test "runs a script, and shows its output only to whoever ran it", %{device: device, product: product, user: user} do
      :ok = link!(user)
      Fixtures.support_script_fixture(product, user, %{name: "disk usage"})
      test_pid = self()

      stub(Runner, :send, fn ran_on, script ->
        send(test_pid, {:ran, ran_on.id, script.name})
        {:ok, "/dev/root 42% <!channel>"}
      end)

      assert %{response_type: "ephemeral", text: "Running `disk usage` on *" <> _} =
               command("script #{device.identifier} disk usage")

      assert_receive {:ran, device_id, "disk usage"}, 2000
      assert device_id == device.id

      assert_receive {:slack, "hooks.slack.com", "/commands/T0ACME/1/abc", body}, 2000
      assert %{"response_type" => "ephemeral", "blocks" => blocks} = Jason.decode!(body)
      texts = for %{"type" => "section", "text" => %{"text" => text}} <- blocks, do: text
      assert "```/dev/root 42% &lt;!channel&gt;```" in texts

      assert [%{"elements" => [%{"action_id" => "script.share", "value" => result_id}]}] =
               Enum.filter(blocks, &(&1["type"] == "actions"))

      assert {:ok, _} = Ecto.UUID.cast(result_id)

      assert [log | _] = AuditLogs.logs_for(device)
      assert log.description =~ "ran support script disk usage on device #{device.identifier} from Slack user U0ALICE"
    end

    test "says so when there is no such script", %{device: device, user: user} do
      :ok = link!(user)

      assert %{text: "There is no support script called `nope`" <> _} = command("script #{device.identifier} nope")
    end
  end
end
