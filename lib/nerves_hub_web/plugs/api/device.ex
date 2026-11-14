defmodule NervesHubWeb.API.Plugs.Device do
  import Plug.Conn

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Scope
  alias NervesHub.Devices

  @preloads [:product, :latest_connection]

  def init(opts) do
    opts
  end

  def call(%{assigns: %{current_scope: %{org: org} = scope}, params: %{"identifier" => identifier}} = conn, _opts)
      when not is_nil(org) do
    device = Devices.get_by_identifier!(scope, identifier, @preloads)

    assign(conn, :device, device)
  end

  # The top-level /api/devices/:identifier routes name no org, so the device's
  # org and the user's role in it go on the scope here, for the permission
  # checks after this plug.
  def call(%{assigns: %{current_scope: scope}, params: %{"identifier" => identifier}} = conn, _opts) do
    device = Devices.get_by_identifier!(scope, identifier, @preloads)
    {:ok, org_user} = Accounts.get_org_user(device.org, scope.user)

    scope =
      scope
      |> Scope.put_org(device.org)
      |> Scope.put_role(OrgUser.assigned_role(org_user))

    conn
    |> assign(:current_scope, scope)
    |> assign(:device, device)
  end
end
