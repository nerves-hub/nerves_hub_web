defmodule NervesHubWeb.Integrations.Slack.UnfurlsTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Accounts
  alias NervesHub.Devices.Connections
  alias NervesHub.Fixtures
  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.UserLink
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHubWeb.Integrations.Slack.Unfurls

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user, %{name: "acme"})
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
      send(test_pid, {:slack, conn.request_path, Jason.decode!(body)})
      Req.Test.json(conn, %{"ok" => true})
    end)

    %{device: device, firmware: firmware, org: org, org_key: org_key, product: product, tmp_dir: tmp_dir, user: user}
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

  defp url(path), do: NervesHubWeb.Endpoint.url() <> path

  defp shared(urls, overrides \\ %{}) do
    Map.merge(
      %{
        "type" => "link_shared",
        "channel" => "C0FLEET",
        "message_ts" => "1728900000.000100",
        "user" => "U0ALICE",
        "source" => "conversations_history",
        "links" => Enum.map(urls, &%{"url" => &1, "domain" => "localhost"})
      },
      overrides
    )
  end

  defp unfurled() do
    assert_received {:slack, "/api/chat.unfurl", body}
    body
  end

  defp fields(%{"blocks" => [%{"fields" => fields} | _]}), do: Enum.map(fields, & &1["text"])

  describe "page/1" do
    test "a device's page, or any of its tabs" do
      assert Unfurls.page(url("/org/acme/thermostat/devices/nh-1")) == {:device, "acme", "thermostat", "nh-1"}

      assert Unfurls.page(url("/org/acme/thermostat/devices/nh-1/health")) ==
               {:device, "acme", "thermostat", "nh-1"}
    end

    test "a deployment group's page, with names decoded" do
      assert Unfurls.page(url("/org/acme/thermo%20stat/deployment_groups/prod%20eu/releases")) ==
               {:deployment_group, "acme", "thermo stat", "prod eu"}
    end

    test "nothing else" do
      assert Unfurls.page(url("/org/acme/thermostat/devices/new")) == nil
      assert Unfurls.page(url("/org/acme/thermostat/devices")) == nil
      assert Unfurls.page("https://elsewhere.example.com/org/acme/thermostat/devices/nh-1") == nil
      assert Unfurls.page("ftp://localhost/org/acme/thermostat/devices/nh-1") == nil
    end
  end

  describe "unfurl/2" do
    test "previews a device's card, without its buttons", %{device: device, user: user} do
      :ok = link!(user)
      link = url("/org/acme/thermostat/devices/#{device.identifier}")

      assert :unfurled = Unfurls.unfurl("T0ACME", shared([link]))

      assert %{"channel" => "C0FLEET", "ts" => "1728900000.000100", "unfurls" => %{^link => preview}} = unfurled()
      assert [%{"type" => "section"}] = preview["blocks"]
      assert "*Connection*\nOnline" in fields(preview)
    end

    test "previews a deployment group's release and where its workflow is", context do
      %{firmware: firmware, org_key: org_key, product: product, tmp_dir: tmp_dir, user: user} = context
      :ok = link!(user)

      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user, name: "production"})

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(
          deployment_group,
          %{
            workflow_definition: %{
              "version" => 1,
              "steps" => [%{"name" => "Sign-off", "type" => "approval_required"}]
            }
          },
          user
        )

      next = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})

      {:ok, {release, _}} =
        ManagedDeployments.create_deployment_release(deployment_group, next, nil, user, %{}, broadcast: false)

      _ = release.id |> Workflows.release_steps() |> hd() |> Workflows.start_step()

      link = url("/org/acme/thermostat/deployment_groups/production")
      assert :unfurled = Unfurls.unfurl("T0ACME", shared([link]))

      assert %{"unfurls" => %{^link => preview}} = unfurled()
      assert [%{"text" => %{"text" => "*production*"}}] = preview["blocks"]

      fields = fields(preview)
      assert "*Status*\nPaused" in fields
      assert "*Release*\n#{release.number}, firmware 2.0.0" in fields
      assert "*Workflow*\nWaiting for approval at Sign-off (step 1 of 2)" in fields
    end

    test "previews a link being typed in the composer by its unfurl id", %{device: device, user: user} do
      :ok = link!(user)
      link = url("/org/acme/thermostat/devices/#{device.identifier}")

      event = shared([link], %{"channel" => "COMPOSER", "source" => "composer", "unfurl_id" => "Uxxxxxxx-909b5454"})
      assert :unfurled = Unfurls.unfurl("T0ACME", event)

      assert %{"unfurl_id" => "Uxxxxxxx-909b5454", "source" => "composer", "unfurls" => %{^link => _}} = unfurled()
    end

    test "asks a poster who has not linked their account to, and previews nothing", %{device: device} do
      link = url("/org/acme/thermostat/devices/#{device.identifier}")

      assert :asked_to_link = Unfurls.unfurl("T0ACME", shared([link]))

      body = unfurled()
      assert %{"user_auth_required" => true, "user_auth_blocks" => blocks} = body
      refute Map.has_key?(body, "unfurls")

      assert [%{"elements" => [%{"url" => link_url}]}] = Enum.filter(blocks, &(&1["type"] == "actions"))
      assert link_url =~ "/integrations/slack/link?team=T0ACME"
    end

    test "previews nothing the poster may not see, and does not say why", %{device: device, org: org} do
      outsider = Fixtures.user_fixture()
      :ok = link!(outsider)

      link = url("/org/acme/thermostat/devices/#{device.identifier}")
      assert :nothing = Unfurls.unfurl("T0ACME", shared([link]))
      refute_received {:slack, _, _}

      # A member of the organization, posting in a workspace it is not
      # connected to.
      member = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, member, %{role: :view})

      _other =
        Fixtures.slack_connection_fixture(Fixtures.org_fixture(member, %{name: "other"}), member, %{team_id: "T0OTHER"})

      Repo.insert!(%UserLink{
        user_id: member.id,
        team_id: "T0OTHER",
        slack_user_id: "U0BOB",
        slack_name: "Bob",
        linked_at: DateTime.utc_now()
      })

      assert :nothing = Unfurls.unfurl("T0OTHER", shared([link], %{"user" => "U0BOB"}))
      refute_received {:slack, _, _}
    end

    test "a viewer sees a device's preview", %{device: device, org: org} do
      viewer = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, viewer, %{role: :view})
      :ok = link!(viewer)

      assert :unfurled =
               Unfurls.unfurl("T0ACME", shared([url("/org/acme/thermostat/devices/#{device.identifier}")]))
    end

    test "leaves out links that are not NervesHub pages, and previews at most five", %{device: device, user: user} do
      :ok = link!(user)
      link = url("/org/acme/thermostat/devices/#{device.identifier}")
      tabs = for tab <- ~w(health logs activity settings console firmware_history), do: "#{link}/#{tab}"

      assert :unfurled = Unfurls.unfurl("T0ACME", shared(["https://example.com/" | tabs]))

      assert %{"unfurls" => unfurls} = unfurled()
      assert map_size(unfurls) == 5
      refute Map.has_key?(unfurls, "https://example.com/")
    end

    test "a missing device is not previewed", %{user: user} do
      :ok = link!(user)

      assert :nothing = Unfurls.unfurl("T0ACME", shared([url("/org/acme/thermostat/devices/nope")]))
      refute_received {:slack, _, _}
    end
  end
end
