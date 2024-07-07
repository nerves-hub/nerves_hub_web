defmodule NervesHubWeb.Components.Navigation do
  use NervesHubWeb, :component

  alias NervesHub.Devices
  alias NervesHub.Products.Product

  import NervesHubWeb.Components.SimpleActiveLink

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
          <ul :if={Enum.any?(@user.orgs)} class="navbar-nav mr-auto flex-grow">
            <li class="nav-item dropdown switcher">
              <a class="nav-link dropdown-toggle org-select arrow-primary" href="#" id="navbarDropdownMenuLink" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                <%= org_name_header(assigns) %>
                <%= if product = assigns[:product] do %>
                  <span class="workspace-divider">:</span> <%= product.name %>
                <% end %>
              </a>

              <div class="dropdown-menu workspace-dropdown" aria-labelledby="navbarDropdownMenuLink">
                <div class="help-text">Select an organization</div>
                <div class="dropdown-divider"></div>
                <%= for org <- @user.orgs do %>
                  <div class="dropdown-submenu">
                    <.link href={~p"/orgs/#{hashid(org)}"} class={"dropdown-item org #{org_classes(@current_path, org.name)}"}>
                      <%= org.name %>
                      <div class="active-checkmark"></div>
                    </.link>
                    <ul class="dropdown-menu">
                      <div class="help-text">Select a product</div>
                      <div class="dropdown-divider"></div>
                      <%= unless Enum.empty?(org.products) do %>
                        <%= for product <- org.products do %>
                          <li>
                            <.link href={~p"/products/#{hashid(product)}/devices"} class={"dropdown-item product #{product_classes(@current_path, product.name)}"}>
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

                      <.link navigate={~p"/orgs/#{hashid(org)}/new"} class="btn btn-outline-light mt-2 mb-3 ml-3 mr-3" aria-label="Create product">
                        <span class="action-text">Create Product</span>
                        <span class="button-icon add"></span>
                      </.link>
                    </ul>
                    <div class="dropdown-divider"></div>
                  </div>
                <% end %>

                <.link navigate={~p"/orgs/new"} class="btn btn-outline-light mt-2 mb-3 ml-3 mr-3" aria-label="Create organization">
                  <span class="action-text">Create Organization</span>
                  <div class="button-icon add"></div>
                </.link>
              </div>
            </li>
          </ul>
          <ul class="navbar-nav">
            <li class="nav-item dropdown">
              <a class="nav-link dropdown-toggle user-menu pr-1" href="#" id="menu1" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                <span><%= @user.name %></span>
                <img src="/images/icons/settings.svg" alt="settings" />
              </a>
              <div class="dropdown-menu dropdown-menu-right" aria-labelledby="navbarDropdownMenuLink">
                <.simple_active_link href={~p"/account"} current_path={@current_path} class="dropdown-item user">
                  My Account
                </.simple_active_link>
                <div class="dropdown-divider"></div>
                <a class="dropdown-item user" href="https://docs.nerves-hub.org/">Documentation</a>
                <div class="dropdown-divider"></div>
                <.link href={~p"/logout"} class="dropdown-item user">Logout</.link>
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

  attr(:user, :any)
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
              <.link class={"nav-link #{link.active}"} navigate={link.href}>
                <span class="text"><%= link.title %></span>
              </.link>
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

  def sidebar_links(["orgs", "new"], _assigns), do: []

  def sidebar_links(["orgs", _org_name] = path, assigns),
    do: sidebar_org(assigns, path)

  def sidebar_links(["orgs", _org_name, "new"] = path, assigns),
    do: sidebar_org(assigns, path)

  def sidebar_links(["orgs", _org_name, "settings" | _tail] = path, assigns),
    do: sidebar_org(assigns, path)

  def sidebar_links(["products", _org_name | _tail] = path, assigns),
    do: sidebar_product(assigns, path)

  def sidebar_links(["account" | _tail] = path, assigns),
    do: sidebar_account(assigns, path)

  def sidebar_links(_path, _assigns), do: []

  def sidebar_org(assigns, path) do
    ([
       %{
         title: "Products",
         active: "",
         href: ~p"/orgs/#{hashid(assigns.org)}"
       }
     ] ++
       if assigns.org_user.role in NervesHub.Accounts.User.role_or_higher(:manage) do
         [
           %{
             title: "Signing Keys",
             active: "",
             href: ~p"/orgs/#{hashid(assigns.org)}/settings/keys"
           },
           %{
             title: "Users",
             active: "",
             href: ~p"/orgs/#{hashid(assigns.org)}/settings/users"
           },
           %{
             title: "Certificates",
             active: "",
             href: ~p"/orgs/#{hashid(assigns.org)}/settings/certificates"
           },
           %{
             title: "Settings",
             active: "",
             href: ~p"/orgs/#{hashid(assigns.org)}/settings"
           }
         ]
       else
         []
       end)
    |> sidebar_active(path)
  end

  def sidebar_product(assigns, path) do
    [
      # %{title: "Dashboard", icon: "tachometer-alt", active: "", href: Routes.product_path(conn, :show, conn.assigns.org.name, conn.assigns.product.name)},
      %{
        title: "Devices",
        active: "",
        href: ~p"/products/#{hashid(assigns.product)}/devices"
      },
      %{
        title: "Firmware",
        active: "",
        href: ~p"/products/#{hashid(assigns.product)}/firmware"
      },
      %{
        title: "Archives",
        active: "",
        href: ~p"/products/#{hashid(assigns.product)}/archives"
      },
      %{
        title: "Deployments",
        active: "",
        href: ~p"/products/#{hashid(assigns.product)}/deployments"
      },
      %{
        title: "Scripts",
        active: "",
        href: ~p"/products/#{hashid(assigns.product)}/scripts"
      },
      %{
        title: "Settings",
        active: "",
        href: ~p"/products/#{hashid(assigns.product)}/settings"
      }
    ]
    |> sidebar_active(path)
  end

  def sidebar_account(_assigns, path) do
    [
      %{
        title: "Personal Info",
        active: "",
        href: ~p"/account"
      },
      %{
        title: "Access Tokens",
        active: "",
        href: ~p"/account/tokens"
      }
    ]
    |> sidebar_active(path)
  end

  defp sidebar_active(links, path) do
    full_path = "/" <> Enum.join(path, "/")
    path_minus_actions = String.replace(full_path, ~r/\/(new|edit|invite|\d+\/edit|upload)$/, "")

    Enum.map(links, fn link ->
      if link.href == path_minus_actions do
        %{link | active: "active"}
      else
        link
      end
    end)
  end

  defp org_classes(current_path, org_name) do
    case path_pieces(current_path) do
      ["orgs", ^org_name | _] ->
        "active"

      _ ->
        "dropdown-toggle"
    end
  end

  defp product_classes(current_path, product_name) do
    case path_pieces(current_path) do
      ["orgs", _, ^product_name | _] ->
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

  defp org_name_header(assigns) do
    cond do
      org = assigns[:org] -> org.name
      product = assigns[:product] -> product.org.name
      true -> "Select Org"
    end
  end
end
