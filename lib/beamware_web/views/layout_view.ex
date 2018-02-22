defmodule BeamwareWeb.LayoutView do
  use BeamwareWeb, :view

  def navigation_links(conn) do
    [
      {"Manage Devices", device_path(conn, :index)},
      {"Manage Firmware", firmware_path(conn, :index)},
      {"Manage Deployments", deployment_path(conn, :index)},
      {"Settings", account_path(conn, :edit)},
      {"Tenant Settings", tenant_path(conn, :edit)}
    ]
  end
end
