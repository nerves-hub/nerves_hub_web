defmodule BeamwareWeb.LayoutView do
  use BeamwareWeb, :view

  alias Beamware.Accounts.User

  def navigation_links(conn) do
    [
      {"Devices", device_path(conn, :index)},
      {"Firmware", firmware_path(conn, :index)},
      {"Deployments", deployment_path(conn, :index)},
      {"Tenant", tenant_path(conn, :edit)},
      {"Account", account_path(conn, :edit)}
    ]
  end

  def logged_in?(%{assigns: %{user: %User{}}}), do: true
  def logged_in?(_), do: false
end
