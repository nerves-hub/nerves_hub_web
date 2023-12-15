defmodule NervesHubWeb.Components.Navigation do
  use NervesHubWeb, :component

  import PhoenixActiveLink

  alias NervesHub.Devices
  alias NervesHub.Products.Product

  attr(:user, :any, default: nil)
  attr(:org, :any, default: nil)
  attr(:orgs, :any, default: nil)
  attr(:product, :any, default: nil)
  attr(:current_path, :string)

  def topbar(assigns) do
    ~H"""
    <nav class="navbar navbar-expand navbar-dark fixed-top flex-md-nowrap p-0 flex-row justify-content-center">
      <div class="content-container flex-row align-items-center justify-content-between h-100">
        <a class="logo" href={~p"/"}>
          <img src="/images/logo.svg" alt="logo" />
          <img src="/images/logo-no-text.svg" alt="logo" class="mobile-logo" />
        </a>

        <%= if @user do %>
          <ul class="navbar-nav mr-auto flex-grow">
            <li class="nav-item dropdown switcher">
              <a class="nav-link dropdown-toggle org-select arrow-primary" href="#" id="navbarDropdownMenuLink" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                <%= if org = assigns[:org], do: org.name, else: "Select Org" %>
                <%= if product = assigns[:product] do %>
                  <span class="workspace-divider">:</span> <%= product.name %>
                <% end %>
              </a>

              <div class="dropdown-menu workspace-dropdown" aria-labelledby="navbarDropdownMenuLink">
                <div class="help-text">Select an organization</div>
                <div class="dropdown-divider"></div>
                <%= for org <- @orgs do %>
                  <div class="dropdown-submenu">
                    <.link href={~p"/org/#{org.name}"} class={"dropdown-item org #{org_classes(@current_path, org.name)}"}>
                      <%= org.name %>
                      <div class="active-checkmark"></div>
                    </.link>
                    <ul class="dropdown-menu">
                      <div class="help-text">Select a product</div>
                      <div class="dropdown-divider"></div>
                      <%= unless Enum.empty?(org.products) do %>
                        <%= for product <- org.products do %>
                          <li>
                            <.link href={~p"/org/#{org.name}/#{product.name}/devices"} class={"dropdown-item product #{product_classes(@current_path, product.name)}"}>
                              <%= product.name %>
                              <div class="active-checkmark"></div>
                            </.link>
                            <div class="dropdown-divider"></div>
                          </li>
                        <% end %>
                      <% else %>
                        <li class="downdown-item product color-white-50 p-3">
                          No Products have been created
                        </li>
                        <div class="dropdown-divider"></div>
                      <% end %>

                      <a class="btn btn-outline-light mt-2 mb-3 ml-3 mr-3" aria-label="Create product" href={~p"/org/#{org.name}/new"}>
                        <span class="action-text">Create Product</span>
                        <span class="button-icon add"></span>
                      </a>
                    </ul>
                    <div class="dropdown-divider"></div>
                  </div>
                <% end %>

                <a class="btn btn-outline-light mt-2 mb-3 ml-3 mr-3" aria-label="Create organization" href={~p"/org/new"}>
                  <span class="action-text">Create Organization</span>
                  <div class="button-icon add"></div>
                </a>
              </div>
            </li>
          </ul>
          <ul class="navbar-nav">
            <li class="nav-item dropdown">
              <a class="nav-link dropdown-toggle user-menu pr-1" href="#" id="menu1" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                <span><%= @user.username %></span>
                <img src="/images/icons/settings.svg" alt="settings" />
              </a>
              <div class="dropdown-menu dropdown-menu-right" aria-labelledby="navbarDropdownMenuLink">
                <%= active_link(%{request_path: @current_path}, "My Account",
                  to: ~p"/account/#{@user.username}",
                  class_active: "dropdown-item user active",
                  class_inactive: "dropdown-item user"
                ) %>
                <div class="dropdown-divider"></div>
                <a class="dropdown-item user" href="https://docs.nerves-hub.org/">Documentation</a>
                <div class="dropdown-divider"></div>
                <.link href={~p"/logout"} method="delete" class="dropdown-item user">Logout</.link>
              </div>
            </li>
          </ul>
        <% else %>
          <div class="navbar-nav">
            <a class="btn btn-outline-light ml-3" href={~p"/login"}>Login</a>
          </div>
        <% end %>
      </div>
    </nav>
    """
  end

  attr(:org, :any, default: nil)
  attr(:product, :any, default: nil)
  attr(:current_path, :string)

  def tabnav(assigns) do
    path = path_pieces(assigns.current_path)
    links = sidebar_links(path, assigns)

    if Enum.any?(links) do
      assigns = %{
        product: assigns.product,
        links: links
      }

      ~H"""
      <div class="tab-bar">
        <nav>
          <ul class="nav">
            <li :for={link <- @links} class="nav-item ">
              <a class={"nav-link #{link.active}"} href={link.href}>
                <span class="text"><%= link.title %></span>
              </a>
            </li>
          </ul>
          <div :if={device_count = device_count(@product)} class="device-limit-indicator" title="Device total" aria-label="Device total">
            <%= device_count %>
          </div>
        </nav>
      </div>
      """
    else
      ~H"""

      """
    end
  end

  def sidebar_links(["org", _org_name | _tail] = path, assigns),
    do: sidebar_product(assigns, path)

  def sidebar_product(assigns, path) do
    [
      # %{title: "Dashboard", icon: "tachometer-alt", active: "", href: Routes.product_path(conn, :show, conn.assigns.org.name, conn.assigns.product.name)},
      %{
        title: "Devices",
        active: "",
        href: ~p"/org/#{assigns.org.name}/#{assigns.product.name}/devices"
      },
      %{
        title: "Firmware",
        active: "",
        href: ~p"/org/#{assigns.org.name}/#{assigns.product.name}/firmware"
      },
      %{
        title: "Archives",
        active: "",
        href: ~p"/org/#{assigns.org.name}/#{assigns.product.name}/archives"
      },
      %{
        title: "Deployments",
        active: "",
        href: ~p"/org/#{assigns.org.name}/#{assigns.product.name}/deployments"
      },
      %{
        title: "Settings",
        active: "",
        href: ~p"/org/#{assigns.org.name}/#{assigns.product.name}/settings"
      }
    ]
    |> sidebar_active(path)
  end

  defp sidebar_active(links, path) do
    full_path = "/" <> Enum.join(path, "/")

    Enum.map(links, fn link ->
      if link.href == full_path do
        %{link | active: "active"}
      else
        link
      end
    end)
  end

  defp org_classes(current_path, org_name) do
    case path_pieces(current_path) do
      ["org", ^org_name | _] ->
        "active"

      _ ->
        "dropdown-toggle"
    end
  end

  defp product_classes(current_path, product_name) do
    case path_pieces(current_path) do
      ["org", _, ^product_name | _] ->
        "active"

      _ ->
        "dropdown-toggle"
    end
  end

  defp path_pieces(path) do
    path
    |> String.trim("/")
    |> String.split("/")
  end

  def device_count(%Product{} = product) do
    Devices.get_device_count_by_product_id(product.id)
  end

  def device_count(_conn) do
    nil
  end
end
