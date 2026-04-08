defmodule NervesHubWeb.Components.Navigation do
  use NervesHubWeb, :component

  import NervesHubWeb.Components.SimpleActiveLink

  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.Devices
  alias NervesHub.Devices.Alarms
  alias NervesHub.Products.Product

  attr(:scope, Scope, required: false)
  attr(:selected_tab, :any)

  def sidebar(%{scope: %{product: product}} = assigns) when not is_nil(product) do
    ~H"""
    <ul role="list">
      <.nav_link
        label="Devices"
        path={~p"/org/#{@scope.org}/#{@scope.product}/devices"}
        selected={:devices == @selected_tab}
        icon="data-[selected=false]:lucide-cpu--light data-[selected=true]:lucide-cpu"
      />
      <.nav_link
        label="Deployment Groups"
        path={~p"/org/#{@scope.org}/#{@scope.product}/deployment_groups"}
        selected={:deployments == @selected_tab}
        icon="data-[selected=false]:lucide-rocket--light data-[selected=true]:lucide-rocket"
      />
      <.nav_link
        label="Firmware"
        path={~p"/org/#{@scope.org}/#{@scope.product}/firmware"}
        selected={:firmware == @selected_tab}
        icon="data-[selected=false]:lucide-binary--light data-[selected=true]:lucide-binary"
      />
      <.nav_link
        label="Archives"
        path={~p"/org/#{@scope.org}/#{@scope.product}/archives"}
        selected={:archives == @selected_tab}
        icon="data-[selected=false]:lucide-archive--light data-[selected=true]:lucide-archive"
      />
      <.nav_link
        label="Support Scripts"
        path={~p"/org/#{@scope.org}/#{@scope.product}/scripts"}
        selected={:support_scripts == @selected_tab}
        icon="data-[selected=false]:lucide-file-code-corner--light data-[selected=true]:lucide-file-code-corner"
      />
      <.nav_link
        label="Notifications"
        path={~p"/org/#{@scope.org}/#{@scope.product}/notifications"}
        selected={:notifications == @selected_tab}
        icon="data-[selected=false]:lucide-bell--light data-[selected=true]:lucide-bell"
      />
      <.nav_link
        label="Settings"
        path={~p"/org/#{@scope.org}/#{@scope.product}/settings"}
        selected={:settings == @selected_tab}
        icon="data-[selected=false]:lucide-settings--light data-[selected=true]:lucide-settings"
      />
    </ul>
    """
  end

  def sidebar(assigns) do
    ~H"""
    <ul role="list">
      <.nav_link label="Products" path={~p"/org/#{@scope.org}/"} selected={:products == @selected_tab} icon="data-[selected=false]:lucide-package--light data-[selected=true]:lucide-package" />
      <.nav_link
        label="Signing Keys"
        path={~p"/org/#{@scope.org}/settings/keys"}
        selected={:signing_keys == @selected_tab}
        icon="data-[selected=false]:lucide-key-round--light data-[selected=true]:lucide-key-round"
      />
      <.nav_link label="Users" path={~p"/org/#{@scope.org}/settings/users"} selected={:users == @selected_tab} icon="data-[selected=false]:lucide-users--light data-[selected=true]:lucide-users" />
      <.nav_link
        label="Certificates"
        path={~p"/org/#{@scope.org}/settings/certificates"}
        selected={:certificates == @selected_tab}
        icon="data-[selected=false]:lucide-shield-check--light data-[selected=true]:lucide-shield-check"
      />
      <.nav_link label="Settings" path={~p"/org/#{@scope.org}/settings"} selected={:settings == @selected_tab} icon="data-[selected=false]:lucide-settings--light data-[selected=true]:lucide-settings" />
    </ul>
    """
  end

  attr(:label, :any)
  attr(:path, :any)
  attr(:selected, :any)
  attr(:icon, :any)

  def nav_link(assigns) do
    ~H"""
    <li
      data-selected={"#{@selected}"}
      class={[
        "data-[selected=true]:border-primary data-[selected=true]:sidebar-item-selected hover:sidebar-item-hover flex h-11 items-center justify-center data-[selected=true]:border-r-2 lg:justify-start lg:px-4"
      ]}
    >
      <.link class="group text-base-300 flex size-full items-center justify-center gap-x-3 text-sm leading-[19px] font-light tracking-wide lg:justify-start" navigate={@path}>
        <span
          data-selected={"#{@selected}"}
          class={"size-5 #{@icon} data-[selected=false]:text-base-500 data-[selected=true]:text-primary"}
        />
        <span class={["hidden lg:inline", @selected && "text-base-50 font-semibold"]}>{@label}</span>
      </.link>
    </li>
    """
  end

  attr(:user, :any, default: nil)
  attr(:org, :any, default: nil)
  attr(:orgs, :any, default: nil)
  attr(:product, :any, default: nil)
  attr(:current_path, :string)

  def topbar(assigns) do
    ~H"""
    <nav class="fixed-top flex-md-nowrap justify-content-center navbar navbar-dark navbar-expand flex-row p-0">
      <div class="align-items-center content-container justify-content-between h-100 flex-row">
        <a class="logo" href={~p"/"}>
          <img src="/images/logo.svg" alt="logo" />
          <img src="/images/logo-no-text.svg" alt="logo" class="mobile-logo" />
        </a>

        <%= if @user do %>
          <ul :if={Enum.any?(@user.orgs)} class="navbar-nav mr-auto grow">
            <li class="dropdown nav-item switcher">
              <a class="arrow-primary dropdown-toggle nav-link org-select" href="#" id="navbarDropdownMenuLink" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                {if org = assigns[:org], do: org.name, else: "Select Org"}
                <%= if product = assigns[:product] do %>
                  <span class="workspace-divider">:</span> {product.name}
                <% end %>
              </a>

              <div class="dropdown-menu workspace-dropdown" aria-labelledby="navbarDropdownMenuLink">
                <div class="help-text">Select an organization</div>
                <div class="dropdown-divider"></div>
                <%= for org <- @user.orgs do %>
                  <div class="dropdown-submenu">
                    <.link navigate={~p"/org/#{org.name}"} class={"dropdown-item org #{org_classes(@current_path, org.name)}"}>
                      {org.name}
                      <div class="active-checkmark"></div>
                    </.link>
                    <ul class="dropdown-menu">
                      <div class="help-text">Select a product</div>
                      <div class="dropdown-divider"></div>
                      <%= unless Enum.empty?(org.products) do %>
                        <%= for product <- org.products do %>
                          <li>
                            <.link navigate={~p"/org/#{org}/#{product}/devices"} class={"dropdown-item product #{product_classes(@current_path, product.name)}"}>
                              {product.name}
                              <div class="active-checkmark"></div>
                            </.link>
                            <div class="dropdown-divider"></div>
                          </li>
                        <% end %>
                      <% else %>
                        <li class="color-white-50 downdown-item product p-3">
                          No Products have been created
                        </li>
                        <div class="dropdown-divider"></div>
                      <% end %>

                      <.link navigate={~p"/org/#{org.name}/new"} class="btn btn-outline-light mx-3 mt-2 mb-3" aria-label="Create product">
                        <span class="action-text">Create Product</span>
                        <span class="add button-icon"></span>
                      </.link>
                    </ul>
                    <div class="dropdown-divider"></div>
                  </div>
                <% end %>

                <.link navigate={~p"/orgs/new"} class="btn btn-outline-light mx-3 mt-2 mb-3" aria-label="Create organization">
                  <span class="action-text">Create Organization</span>
                  <div class="add button-icon"></div>
                </.link>
              </div>
            </li>
          </ul>
          <ul class="navbar-nav">
            <li class="dropdown nav-item">
              <a class="dropdown-toggle nav-link user-menu pr-1" href="#" id="menu1" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                <span>{@user.name}</span>
                <img src="/images/icons/settings.svg" alt="settings" />
              </a>
              <div class="dropdown-menu dropdown-menu-right" aria-labelledby="navbarDropdownMenuLink">
                <.simple_active_link navigate={~p"/account"} current_path={@current_path} class="dropdown-item user">
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

  def simple_topbar(assigns) do
    ~H"""
    <div class="border-base-700 flex h-14 shrink-0 items-center border-r border-b px-4">
      <svg width="111" height="24" viewBox="0 0 111 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path
          d="M27.6721 0.0260367C28.4368 0.0260367 29.0567 0.656731 29.0567 1.43473V22.571C29.0567 23.349 28.4368 23.9797 27.6721 23.9797H22.1135L22.1163 23.9915C21.8164 23.9877 21.5258 23.8847 21.2885 23.698L7.79999 13.4673C7.44479 13.1961 7.23799 12.7687 7.24316 12.3169V11.7299C7.24264 11.2 7.53439 10.7146 7.99832 10.4736C8.46224 10.2327 9.01983 10.277 9.44133 10.5883L22.2779 20.053C22.5149 20.2264 22.7994 20.3198 23.0913 20.3201H24.0692C24.4367 20.3208 24.7893 20.1727 25.0491 19.9083C25.309 19.644 25.4546 19.2852 25.4538 18.9114V5.09734C25.4546 4.72349 25.309 4.36473 25.0491 4.10038C24.7893 3.83603 24.4367 3.68786 24.0692 3.68865H23.0365C22.6691 3.68943 22.3164 3.54126 22.0566 3.27691C21.7968 3.01256 21.6511 2.6538 21.6519 2.27995V1.43473C21.6519 0.656731 22.2718 0.0260367 23.0365 0.0260367H27.6721ZM39.0606 15.3192V18.6267H41.1404V15.3192H43.3356V23.9797H41.1404V20.5402H39.0606V23.9797H36.8654V15.3192H39.0606ZM53.1836 15.3192V21.9782C53.188 22.0406 53.2376 22.0898 53.299 22.0927H54.9C54.9692 22.0995 55.0309 22.0485 55.0385 21.9782V15.3192H57.2337V22.9907C57.2383 23.2524 57.139 23.5049 56.9582 23.6911C56.7773 23.8773 56.5303 23.9814 56.2731 23.9798H51.9606C51.4248 23.9781 50.9913 23.5358 50.9913 22.9907V15.3192H53.1836ZM70.94 15.602C71.157 15.8087 71.2771 16.0998 71.2702 16.4021V18.3273C71.2702 18.9143 70.8923 19.4836 70.1163 19.6744C70.8981 19.8681 71.3394 20.4052 71.3394 20.9833V22.8704C71.3552 23.1771 71.2386 23.4756 71.0202 23.6876C70.8018 23.8997 70.5033 24.0042 70.2029 23.9739L64.8894 23.9797V15.3192H70.1336C70.4298 15.2924 70.7231 15.3952 70.94 15.602ZM6.9721 0.00549316C7.2721 0.00908025 7.56276 0.112117 7.79999 0.298972L21.2885 10.5326C21.6429 10.8026 21.8479 11.2296 21.8394 11.6801V12.267C21.8392 12.7959 21.5479 13.2802 21.085 13.5209C20.6221 13.7616 20.0657 13.7183 19.6442 13.4086L6.81345 3.95278C6.5773 3.77729 6.29242 3.68274 5.99999 3.68278H5.01345C4.64573 3.68278 4.29311 3.83159 4.03336 4.09641C3.77361 4.36123 3.62807 4.72029 3.62883 5.09441V18.8996C3.62883 19.6776 4.24875 20.3083 5.01345 20.3083H6.05768C6.42514 20.3075 6.77777 20.4557 7.0376 20.7201C7.29743 20.9844 7.44306 21.3432 7.4423 21.717V22.5652C7.44309 22.9411 7.29587 23.3016 7.03354 23.5663C6.7712 23.831 6.41559 23.9778 6.04614 23.9739H1.41345C0.648746 23.9739 0.0288204 23.3432 0.0288204 22.5652V1.43473C0.0272982 1.06011 0.172499 0.70029 0.432332 0.434838C0.692164 0.169385 1.04522 0.0201639 1.41345 0.0201672H6.9721V0.00549316ZM69.0462 20.4257H67.0788V22.3363H69.0462C69.0806 22.3389 69.1144 22.3262 69.1388 22.3014C69.1632 22.2765 69.1757 22.2421 69.1731 22.2071V20.5666C69.1763 20.5303 69.1644 20.4944 69.1402 20.4676C69.1161 20.4408 69.0819 20.4256 69.0462 20.4257ZM69.0462 17.036H67.0788V18.8351H69.0462C69.1356 18.8351 69.1731 18.7705 69.1731 18.6913V17.1798C69.1763 17.1433 69.1644 17.1071 69.1404 17.0798C69.1163 17.0526 69.0822 17.0367 69.0462 17.036ZM109.399 2.96962V4.83028H106.321C106.286 4.831 106.252 4.84646 106.228 4.87308C106.204 4.89969 106.192 4.93513 106.194 4.97115V6.24191C106.202 6.30744 106.256 6.35679 106.321 6.35636H108.516C108.785 6.34175 109.047 6.44413 109.237 6.63792C109.427 6.8317 109.527 7.09857 109.512 7.3718V10.6177C109.526 10.8904 109.426 11.1565 109.236 11.3496C109.07 11.5186 108.849 11.6178 108.616 11.6302L104.002 11.6302V9.75778H107.192C107.279 9.75778 107.331 9.70495 107.331 9.64332V8.3843C107.331 8.31973 107.279 8.26984 107.192 8.26984H104.997C104.729 8.28446 104.466 8.18207 104.277 7.98829C104.11 7.81872 104.013 7.59321 104.002 7.35644L104.002 3.98506C103.987 3.71183 104.087 3.44496 104.277 3.25118C104.443 3.08161 104.664 2.98203 104.897 2.96958L109.399 2.96962ZM38.8846 2.96962L41.4317 7.74158V2.96962H43.4481V11.6302H41.3683L38.8846 6.86995V11.6302H36.8654V2.96962H38.8846ZM56.7894 2.96962V4.83028H53.4086V6.34462H56.3365V8.19354H53.4086V9.75778H56.7894V11.6302H51.2279V2.96962H56.7894ZM69.6144 2.96962C70.1433 2.96962 70.5721 3.40585 70.5721 3.94397V7.90886C70.5644 8.44418 70.1406 8.8767 69.6144 8.88615H69.551L70.5981 11.6302H68.4548L67.3933 8.88615H66.4615V11.6302H64.2692V2.96962H69.6144ZM79.4106 2.96962L80.5962 8.47528L82.0211 2.96962H84.1904L81.6548 11.6302H79.5375L77.0654 2.96962H79.4106ZM96.701 2.96962V4.83028H93.3202V6.34462H96.2452V8.19354H93.3202V9.75778H96.701V11.6302H91.1394V2.96962H96.701ZM68.276 4.82734H66.4615V7.13701H68.276C68.3349 7.12878 68.3818 7.08235 68.3913 7.02256V4.95647C68.3879 4.891 68.3397 4.83701 68.276 4.82734Z"
          fill="#FAFAFA"
        >
        </path>
        <path
          d="M29.0567 1.43461C29.0567 0.656609 28.4368 0.0259147 27.6721 0.0259147H23.0365C22.2718 0.0259147 21.6519 0.656609 21.6519 1.43461V2.27983C21.6511 2.65368 21.7968 3.01244 22.0566 3.27679C22.3164 3.54114 22.6691 3.6893 23.0365 3.68852H24.0692C24.4367 3.68774 24.7893 3.83591 25.0491 4.10026C25.309 4.36461 25.4546 4.72337 25.4538 5.09722V18.9112C25.4546 19.2851 25.309 19.6439 25.0491 19.9082C24.7893 20.1726 24.4367 20.3207 24.0692 20.3199H23.0913C22.7994 20.3196 22.5149 20.2262 22.2779 20.0529L9.44133 10.5882C9.01983 10.2769 8.46224 10.2325 7.99832 10.4735C7.53439 10.7144 7.24264 11.1999 7.24316 11.7298V12.3168C7.23799 12.7686 7.44479 13.1959 7.79999 13.4672L21.2885 23.6979C21.5258 23.8845 21.8164 23.9876 22.1163 23.9914L22.1135 23.9796H27.6721C28.4368 23.9796 29.0567 23.3489 29.0567 22.5709V1.43461Z"
          fill="#6366F1"
        >
        </path>
        <path
          d="M7.79999 0.298849C7.56276 0.111995 7.2721 0.00895818 6.9721 0.00537109V0.0200451H1.41345C1.04522 0.0200419 0.692164 0.169263 0.432332 0.434716C0.172499 0.700168 0.0272982 1.05999 0.0288204 1.43461V22.565C0.0288204 23.343 0.648746 23.9738 1.41345 23.9738H6.04614C6.41559 23.9777 6.7712 23.8309 7.03354 23.5662C7.29587 23.3015 7.44309 22.9409 7.4423 22.565V21.7169C7.44306 21.343 7.29743 20.9843 7.0376 20.7199C6.77777 20.4556 6.42514 20.3074 6.05768 20.3082H5.01345C4.24875 20.3082 3.62883 19.6775 3.62883 18.8995V5.09428C3.62807 4.72017 3.77361 4.36111 4.03336 4.09629C4.29311 3.83147 4.64573 3.68265 5.01345 3.68265H5.99999C6.29242 3.68261 6.5773 3.77717 6.81345 3.95265L19.6442 13.4085C20.0657 13.7182 20.6221 13.7615 21.085 13.5208C21.5479 13.28 21.8392 12.7958 21.8394 12.2669V11.6799C21.8479 11.2295 21.6429 10.8025 21.2885 10.5324L7.79999 0.298849Z"
          fill="#6366F1"
        >
        </path>
      </svg>
    </div>
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
        org: assigns.org,
        product: assigns.product,
        links: links
      }

      ~H"""
      <div class="tab-bar">
        <nav>
          <ul class="nav">
            <li :for={link <- @links} class="nav-item">
              <.link class={"nav-link #{link.active}"} navigate={link.href}>
                <span class="text">{link.title}</span>
              </.link>
            </li>
          </ul>
          <div class="align-items-center justify-content-between flex-row">
            <div :if={device_count = device_count(@product)} class="device-limit-indicator navbar-indicator" title="Device total" aria-label="Device total">
              {device_count}
            </div>
            <.link
              :if={alarms_count = alarms_count(@product)}
              navigate={~p"/org/#{@org}/#{@product}/devices?alarm_status=with"}
              class="alarms-indicator navbar-indicator"
              title="Devices alarming"
              aria-label="Devices alarming"
            >
              {alarms_count}
            </.link>
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

  def sidebar_links(["org", _org_name] = path, assigns), do: sidebar_org(assigns, path)

  def sidebar_links(["org", _org_name, "new"] = path, assigns), do: sidebar_org(assigns, path)

  def sidebar_links(["org", _org_name, "settings" | _tail] = path, assigns), do: sidebar_org(assigns, path)

  def sidebar_links(["org", _org_name | _tail] = path, assigns), do: sidebar_product(assigns, path, assigns[:tab_hint])

  def sidebar_links(["account" | _tail] = path, assigns), do: sidebar_account(assigns, path)

  def sidebar_links(_path, _assigns), do: []

  def sidebar_org(assigns, path) do
    ([
       %{
         title: "Products",
         active: "",
         href: ~p"/org/#{assigns.org}"
       }
     ] ++
       if assigns.org_user.role in User.role_or_higher(:manage) do
         [
           %{
             title: "Signing Keys",
             active: "",
             href: ~p"/org/#{assigns.org}/settings/keys"
           },
           %{
             title: "Users",
             active: "",
             href: ~p"/org/#{assigns.org}/settings/users"
           },
           %{
             title: "Certificates",
             active: "",
             href: ~p"/org/#{assigns.org}/settings/certificates"
           },
           %{
             title: "Settings",
             active: "",
             href: ~p"/org/#{assigns.org}/settings"
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
        title: "Devices",
        active: "",
        href: ~p"/org/#{assigns.org}/#{assigns.product}/devices",
        tab: :devices
      },
      %{
        title: "Firmware",
        active: "",
        href: ~p"/org/#{assigns.org}/#{assigns.product}/firmware"
      },
      %{
        title: "Archives",
        active: "",
        href: ~p"/org/#{assigns.org}/#{assigns.product}/archives"
      },
      %{
        title: "Deployments",
        active: "",
        href: ~p"/org/#{assigns.org}/#{assigns.product}/deployment_groups"
      },
      %{
        title: "Scripts",
        active: "",
        href: ~p"/org/#{assigns.org}/#{assigns.product}/scripts"
      },
      %{
        title: "Settings",
        active: "",
        href: ~p"/org/#{assigns.org}/#{assigns.product}/settings"
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

  def alarms_count(%Product{} = product), do: Alarms.current_alarms_count(product.id)
  def alarms_count(_conn), do: nil
end
