defmodule NervesHubWeb.DeviceLiveIndexTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  import Phoenix.ChannelTest

  alias NervesHub.{AuditLogs, Fixtures, Repo}
  alias NervesHubWeb.Endpoint

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  describe "handle_event" do
    test "reboot allowed", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture
      {:ok, view, _html} = live(conn, device_index_path(fixture))

      before_audit_count = AuditLogs.logs_for(device) |> length

      assert render_change(view, :reboot, %{"device-id" => device.id}) =~ "reboot requested"
      assert_broadcast("reboot", %{})

      after_audit_count = AuditLogs.logs_for(device) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "reboot blocked", %{conn: conn, fixture: fixture} do
      %{device: device, user: user} = fixture

      Repo.preload(user, :org_users)
      |> Map.get(:org_users)
      |> Enum.map(&NervesHub.Accounts.change_org_user_role(&1, :read))

      {:ok, view, _html} = live(conn, device_index_path(fixture))

      before_audit_count = AuditLogs.logs_for(device) |> length

      assert render_change(view, :reboot, %{"device-id" => device.id}) =~ "reboot blocked"

      after_audit_count = AuditLogs.logs_for(device) |> length

      assert after_audit_count == before_audit_count + 1
    end

    test "filters devices by field", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      {:ok, view, html} = live(conn, device_index_path(fixture))
      assert html =~ device2.identifier

      refute render_change(view, "update-filters", %{"id" => device.identifier}) =~
               device2.identifier
    end

    test "filters devices by tag", %{conn: conn, fixture: fixture} do
      %{device: _device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: ["filtertest"]})

      {:ok, view, html} = live(conn, device_index_path(fixture))
      assert html =~ device2.identifier

      refute render_change(view, "update-filters", %{"tag" => "filtertest-noshow"}) =~
               device2.identifier

      assert render_change(view, "update-filters", %{"tag" => "filtertest"}) =~
               device2.identifier
    end

    test "filters devices with no tags", %{conn: conn, fixture: fixture} do
      %{device: _device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})

      {:ok, view, html} = live(conn, device_index_path(fixture))
      assert html =~ device2.identifier

      refute render_change(view, "update-filters", %{"tag" => "doesntmatter"}) =~
               device2.identifier
    end

    test "paginates devices", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)
      device3 = Fixtures.device_fixture(org, product, firmware)

      {:ok, view, _html} = live(conn, device_index_path(fixture))
      html = render_change(view, "set-paginate-opts", %{"page-size" => "1"})

      assert html =~ device.identifier
      refute html =~ device2.identifier

      html = render_change(view, "paginate", %{"page" => "2"})
      assert html =~ device2.identifier
      refute html =~ device.identifier

      html = render_change(view, "set-paginate-opts", %{"page-size" => "1"})
      assert html =~ device2.identifier

      html = render_change(view, "paginate", %{"page" => "3"})
      refute html =~ device.identifier
      refute html =~ device2.identifier
      assert html =~ device3.identifier

      html = render_change(view, "set-paginate-opts", %{"page-size" => "2"})
      assert html =~ device3.identifier

      html = render_change(view, "paginate", %{"page" => "2"})
      refute html =~ device.identifier
      refute html =~ device2.identifier
      assert html =~ device3.identifier
    end
  end

  def device_index_path(%{org: org, product: product}) do
    Routes.device_path(Endpoint, :index, org.name, product.name)
  end
end
