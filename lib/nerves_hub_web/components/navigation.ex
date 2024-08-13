defmodule NervesHubWeb.Components.Navigation do
  use NervesHubWeb, :component

  alias NervesHub.Devices
  alias NervesHub.Products.Product

  import NervesHubWeb.Components.SimpleActiveLink

  attr(:org, :any)
  attr(:product, :any)

  def updated_sidebar(assigns) do
    ~H"""
    <nav class="flex flex-1 flex-col">
      <ul role="list" class="flex flex-1 flex-col">
        <li>
          <ul role="list">
            <li class="h-11 flex items-center py-2 px-4 sidebar-item-selected">
              <.link class="group flex items-center gap-x-3 text-sm tracking-wide leading-[19px] w-full h-full" navigate={~p"/org/#{@org.name}/#{@product.name}/devices"}>
                <svg class="w-5 h-5 stroke-[#6366F1]" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M2.5 10.8333H17.5M2.5 10.8333V14.1666C2.5 15.0871 3.24619 15.8333 4.16667 15.8333H15.8333C16.7538 15.8333 17.5 15.0871 17.5 14.1666V10.8333M2.5 10.8333L3.85106 5.42907C4.03654 4.68712 4.70318 4.16663 5.46796 4.16663H14.532C15.2968 4.16663 15.9635 4.68712 16.1489 5.42907L17.5 10.8333M5 13.3333H15"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
                <span class="pt-0.5">
                  Devices
                </span>
              </.link>
            </li>
            <li class="h-11 flex items-center py-2 px-4">
              <.link class="group flex items-center gap-x-3 text-sm tracking-wide leading-[19px] text-[#D4D4D8] font-light  w-full h-full" navigate={~p"/org/#{@org.name}/#{@product.name}/deployments"}>
                <svg class="w-5 h-5 stroke-[#71717A]" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M9.99992 2.5L14.1666 6.66667M9.99992 2.5L5.83325 6.66667M9.99992 2.5V10.8333M11.6667 15.8333C11.6667 16.7538 10.9205 17.5 10 17.5C9.07955 17.5 8.33335 16.7538 8.33335 15.8333C8.33335 14.9129 9.07955 14.1667 10 14.1667C10.9205 14.1667 11.6667 14.9129 11.6667 15.8333Z"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
                <span class="pt-0.5">
                  Deployments
                </span>

              </.link>
            </li>
            <li class="h-11 flex items-center py-2 px-4">
              <.link class="group flex gap-x-3 text-sm leading-5 text-[#D4D4D8] font-light" navigate={~p"/org/#{@org.name}/#{@product.name}/firmware"}>
                <svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M5.83333 6.66659H10M12.5 6.66659H14.1667M14.1667 9.99992H9.16667M6.66667 9.99992H5.83333M5.83333 13.3333H10M12.5 13.3333H14.1667M4.16667 16.6666H15.8333C16.7538 16.6666 17.5 15.9204 17.5 14.9999V4.99992C17.5 4.07944 16.7538 3.33325 15.8333 3.33325H4.16667C3.24619 3.33325 2.5 4.07944 2.5 4.99992V14.9999C2.5 15.9204 3.24619 16.6666 4.16667 16.6666Z"
                    stroke="#71717A"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>

                <span class="pt-0.5">
                  Firmware
                </span>
              </.link>
            </li>
            <li class="h-11 flex items-center py-2 px-4">
              <.link class="group flex gap-x-3 text-sm leading-5 text-[#D4D4D8] font-light" navigate={~p"/org/#{@org.name}/#{@product.name}/artifacts"}>
                <svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M3.33333 6.66659V14.9999C3.33333 15.9204 4.07953 16.6666 5 16.6666H15C15.9205 16.6666 16.6667 15.9204 16.6667 14.9999V6.66659M3.33333 6.66659H16.6667M3.33333 6.66659C2.8731 6.66659 2.5 6.29349 2.5 5.83325V4.99992C2.5 4.07944 3.24619 3.33325 4.16667 3.33325H15.8333C16.7538 3.33325 17.5 4.07944 17.5 4.99992V5.83325C17.5 6.29349 17.1269 6.66659 16.6667 6.66659M8.33333 9.99992H11.6667"
                    stroke="#71717A"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>

                <span class="pt-0.5">
                  Artifacts
                </span>
              </.link>
            </li>
            <li class="h-11 flex items-center py-2 px-4">
              <.link class="group flex gap-x-3 text-sm leading-5 text-[#D4D4D8] font-light" navigate={~p"/org/#{@org.name}/#{@product.name}/scripts"}>
                <svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M5.83333 6.66675L2.5 10.0001L5.83333 13.3334M14.1667 13.3334L17.5 10.0001L14.1667 6.66675M11.6667 4.16675L8.33333 15.8334"
                    stroke="#71717A"
                    stroke-width="1.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>

                <span class="pt-0.5">
                  Support Scripts
                </span>
              </.link>
            </li>
            <li class="h-11 flex items-center py-2 px-4">
              <.link class="group flex gap-x-3 text-sm leading-5 text-[#D4D4D8] font-light" navigate={~p"/org/#{@org.name}/#{@product.name}/settings"}>
                <svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M8.33328 17.5L7.74757 17.6302C7.80857 17.9047 8.05206 18.1 8.33328 18.1V17.5ZM11.6666 17.5V18.1C11.9478 18.1 12.1913 17.9047 12.2523 17.6302L11.6666 17.5ZM11.6666 2.5L12.2523 2.36984C12.1913 2.09532 11.9478 1.9 11.6666 1.9V2.5ZM8.33328 2.5V1.9C8.05206 1.9 7.80857 2.09532 7.74757 2.36984L8.33328 2.5ZM2.67139 12.3066L2.26581 11.8645C2.05857 12.0545 2.01116 12.3631 2.15177 12.6066L2.67139 12.3066ZM4.33805 15.1934L3.81844 15.4934C3.95905 15.7369 4.24994 15.8501 4.51819 15.7657L4.33805 15.1934ZM17.3284 7.69337L17.734 8.13553C17.9413 7.94544 17.9887 7.63691 17.8481 7.39337L17.3284 7.69337ZM15.6618 4.80662L16.1814 4.50662C16.0408 4.26307 15.7499 4.14987 15.4816 4.2343L15.6618 4.80662ZM4.33805 4.80662L4.51819 4.23429C4.24994 4.14987 3.95905 4.26307 3.81844 4.50662L4.33805 4.80662ZM2.67139 7.69337L2.15177 7.39337C2.01116 7.63691 2.05857 7.94544 2.26581 8.13553L2.67139 7.69337ZM15.6618 15.1934L15.4816 15.7657C15.7499 15.8501 16.0408 15.7369 16.1814 15.4934L15.6618 15.1934ZM17.3284 12.3066L17.8481 12.6066C17.9887 12.3631 17.9413 12.0545 17.734 11.8645L17.3284 12.3066ZM15.768 9.12465L15.3625 8.68249C15.2154 8.81739 15.145 9.01659 15.1747 9.21394L15.768 9.12465ZM15.768 10.8753L15.1747 10.786C15.145 10.9834 15.2154 11.1826 15.3625 11.3175L15.768 10.8753ZM13.6414 14.5575L13.8215 13.9851C13.6308 13.9251 13.4227 13.964 13.2665 14.0889L13.6414 14.5575ZM12.1258 15.4339L11.907 14.8752C11.721 14.948 11.5834 15.1087 11.54 15.3037L12.1258 15.4339ZM7.87414 15.4339L8.45985 15.3037C8.41651 15.1087 8.27892 14.948 8.09288 14.8752L7.87414 15.4339ZM6.35851 14.5574L6.73334 14.0889C6.5772 13.964 6.3691 13.9251 6.17837 13.9851L6.35851 14.5574ZM4.23184 10.8753L4.63742 11.3174C4.78449 11.1825 4.85486 10.9833 4.82516 10.786L4.23184 10.8753ZM4.23184 9.1247L4.82516 9.21398C4.85486 9.01664 4.78449 8.81744 4.63742 8.68254L4.23184 9.1247ZM6.35852 5.44255L6.17839 6.01487C6.36912 6.0749 6.57722 6.03598 6.73335 5.91106L6.35852 5.44255ZM7.87414 4.56613L8.09288 5.12483C8.27892 5.05199 8.41651 4.89132 8.45985 4.69629L7.87414 4.56613ZM13.6413 5.44254L13.2665 5.91105C13.4227 6.03596 13.6308 6.07489 13.8215 6.01486L13.6413 5.44254ZM12.1258 4.56613L11.54 4.69629C11.5834 4.89132 11.721 5.05199 11.907 5.12483L12.1258 4.56613ZM8.33328 18.1H11.6666V16.9H8.33328V18.1ZM11.6666 1.9H8.33328V3.1H11.6666V1.9ZM2.15177 12.6066L3.81844 15.4934L4.85767 14.8934L3.191 12.0066L2.15177 12.6066ZM17.8481 7.39337L16.1814 4.50662L15.1422 5.10662L16.8088 7.99337L17.8481 7.39337ZM3.81844 4.50662L2.15177 7.39337L3.191 7.99337L4.85767 5.10662L3.81844 4.50662ZM16.1814 15.4934L17.8481 12.6066L16.8088 12.0066L15.1422 14.8934L16.1814 15.4934ZM15.1747 9.21394C15.2133 9.47001 15.2333 9.73248 15.2333 10H16.4333C16.4333 9.6725 16.4088 9.35035 16.3614 9.03537L15.1747 9.21394ZM16.1736 9.56681L17.734 8.13553L16.9229 7.25121L15.3625 8.68249L16.1736 9.56681ZM15.2333 10C15.2333 10.2675 15.2133 10.53 15.1747 10.786L16.3614 10.9646C16.4088 10.6496 16.4333 10.3275 16.4333 10H15.2333ZM17.734 11.8645L16.1736 10.4332L15.3625 11.3175L16.9229 12.7488L17.734 11.8645ZM13.4612 15.1298L15.4816 15.7657L15.8419 14.621L13.8215 13.9851L13.4612 15.1298ZM13.2665 14.0889C12.8585 14.4154 12.4009 14.6818 11.907 14.8752L12.3445 15.9926C12.9525 15.7545 13.5151 15.4268 14.0162 15.026L13.2665 14.0889ZM12.2523 17.6302L12.7115 15.564L11.54 15.3037L11.0809 17.3698L12.2523 17.6302ZM7.28843 15.564L7.74757 17.6302L8.91899 17.3698L8.45985 15.3037L7.28843 15.564ZM8.09288 14.8752C7.59902 14.6818 7.14138 14.4154 6.73334 14.0889L5.98367 15.0259C6.48473 15.4268 7.04736 15.7545 7.6554 15.9926L8.09288 14.8752ZM4.51819 15.7657L6.53864 15.1298L6.17837 13.9851L4.15792 14.621L4.51819 15.7657ZM4.82516 10.786C4.78663 10.5299 4.76661 10.2675 4.76661 10H3.56661C3.56661 10.3275 3.59113 10.6496 3.63852 10.9646L4.82516 10.786ZM3.82626 10.4331L2.26581 11.8645L3.07696 12.7488L4.63742 11.3174L3.82626 10.4331ZM4.76661 10C4.76661 9.73249 4.78663 9.47004 4.82516 9.21398L3.63852 9.03542C3.59113 9.35039 3.56661 9.67252 3.56661 10H4.76661ZM2.26581 8.13553L3.82627 9.56687L4.63742 8.68254L3.07696 7.2512L2.26581 8.13553ZM6.53866 4.87023L4.51819 4.23429L4.15792 5.37894L6.17839 6.01487L6.53866 4.87023ZM6.73335 5.91106C7.14139 5.58461 7.59903 5.31818 8.09288 5.12483L7.6554 4.00742C7.04737 4.24547 6.48474 4.57318 5.98369 4.97404L6.73335 5.91106ZM7.74757 2.36984L7.28843 4.43597L8.45985 4.69629L8.91899 2.63016L7.74757 2.36984ZM15.4816 4.2343L13.4612 4.87021L13.8215 6.01486L15.8419 5.37894L15.4816 4.2343ZM11.907 5.12483C12.4009 5.31818 12.8585 5.5846 13.2665 5.91105L14.0162 4.97402C13.5151 4.57317 12.9525 4.24547 12.3445 4.00742L11.907 5.12483ZM12.7115 4.43597L12.2523 2.36984L11.0809 2.63016L11.54 4.69629L12.7115 4.43597ZM11.8999 10C11.8999 11.0493 11.0493 11.9 9.99994 11.9V13.1C11.712 13.1 13.0999 11.7121 13.0999 10H11.8999ZM9.99994 11.9C8.9506 11.9 8.09994 11.0493 8.09994 10H6.89994C6.89994 11.7121 8.28786 13.1 9.99994 13.1V11.9ZM8.09994 10C8.09994 8.95066 8.9506 8.1 9.99994 8.1V6.9C8.28786 6.9 6.89994 8.28792 6.89994 10H8.09994ZM9.99994 8.1C11.0493 8.1 11.8999 8.95066 11.8999 10H13.0999C13.0999 8.28792 11.712 6.9 9.99994 6.9V8.1Z"
                    fill="#71717A"
                  />
                </svg>

                <span class="pt-0.5">
                  Settings
                </span>
              </.link>
            </li>
          </ul>
        </li>
      </ul>
    </nav>
    """
  end

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
                <%= if org = assigns[:org], do: org.name, else: "Select Org" %>
                <%= if product = assigns[:product] do %>
                  <span class="workspace-divider">:</span> <%= product.name %>
                <% end %>
              </a>

              <div class="dropdown-menu workspace-dropdown" aria-labelledby="navbarDropdownMenuLink">
                <div class="help-text">Select an organization</div>
                <div class="dropdown-divider"></div>
                <%= for org <- @user.orgs do %>
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

                      <.link navigate={~p"/org/#{org.name}/new"} class="btn btn-outline-light mt-2 mb-3 ml-3 mr-3" aria-label="Create product">
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
  attr(:tab, :any, default: nil)
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

  def sidebar_links(["org", _org_name] = path, assigns),
    do: sidebar_org(assigns, path)

  def sidebar_links(["org", _org_name, "new"] = path, assigns),
    do: sidebar_org(assigns, path)

  def sidebar_links(["org", _org_name, "settings" | _tail] = path, assigns),
    do: sidebar_org(assigns, path)

  def sidebar_links(["org", _org_name | _tail] = path, assigns),
    do: sidebar_product(assigns, path, assigns[:tab_hint])

  def sidebar_links(["account" | _tail] = path, assigns),
    do: sidebar_account(assigns, path)

  def sidebar_links(_path, _assigns), do: []

  def sidebar_org(assigns, path) do
    ([
       %{
         title: "Products",
         active: "",
         href: ~p"/org/#{assigns.org.name}"
       }
     ] ++
       if assigns.org_user.role in NervesHub.Accounts.User.role_or_higher(:manage) do
         [
           %{
             title: "Signing Keys",
             active: "",
             href: ~p"/org/#{assigns.org.name}/settings/keys"
           },
           %{
             title: "Users",
             active: "",
             href: ~p"/org/#{assigns.org.name}/settings/users"
           },
           %{
             title: "Certificates",
             active: "",
             href: ~p"/org/#{assigns.org.name}/settings/certificates"
           },
           %{
             title: "Settings",
             active: "",
             href: ~p"/org/#{assigns.org.name}/settings"
           }
         ]
       else
         []
       end)
    |> sidebar_active(path)
  end

  def sidebar_product(assigns, path, tab_hint) do
    [
      %{
        title: "Dashboard",
        active: "",
        href: ~p"/org/#{assigns.org.name}/#{assigns.product.name}/dashboard",
        deactivated?: Application.get_env(:nerves_hub, :dashboard_enabled) != true
      },
      %{
        title: "Devices",
        active: "",
        href: ~p"/org/#{assigns.org.name}/#{assigns.product.name}/devices",
        tab: :devices
      },
      %{
        title: "Firmware",
        active: "",
        href: ~p"/org/#{assigns.org.name}/#{assigns.product.name}/firmware"
      },
      %{
        title: "Artifacts",
        active: "",
        href: ~p"/org/#{assigns.org.name}/#{assigns.product.name}/artifacts"
      },
      %{
        title: "Deployments",
        active: "",
        href: ~p"/org/#{assigns.org.name}/#{assigns.product.name}/deployments"
      },
      %{
        title: "Scripts",
        active: "",
        href: ~p"/org/#{assigns.org.name}/#{assigns.product.name}/scripts"
      },
      %{
        title: "Settings",
        active: "",
        href: ~p"/org/#{assigns.org.name}/#{assigns.product.name}/settings"
      }
    ]
    |> Enum.reject(& &1[:deactivated?])
    |> sidebar_active(path, tab_hint)
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

  defp sidebar_active(links, path, tab_hint \\ nil) do
    full_path = "/" <> Enum.join(path, "/")
    path_minus_actions = String.replace(full_path, ~r/\/(new|edit|invite|\d+\/edit|upload)$/, "")

    Enum.map(links, fn link ->
      cond do
        link[:tab] && link[:tab] == tab_hint ->
          %{link | active: "active"}

        link.href == path_minus_actions ->
          %{link | active: "active"}

        true ->
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
