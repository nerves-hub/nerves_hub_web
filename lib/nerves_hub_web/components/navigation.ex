defmodule NervesHubWeb.Components.Navigation do
  use NervesHubWeb, :component

  alias NervesHub.Accounts.Scope
  alias NervesHub.ProductNotifications

  attr(:scope, Scope, required: false)
  attr(:selected_tab, :any)

  def sidebar(%{scope: %{product: product}} = assigns) when not is_nil(product) do
    count =
      ProductNotifications.count(product)
      |> case do
        0 -> nil
        n -> n
      end

    assigns = assign(assigns, :notifications_count, count)

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
        badge={@notifications_count}
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
  attr(:badge, :any, default: nil)
  attr(:path, :any)
  attr(:selected, :any)
  attr(:icon, :any)

  def nav_link(assigns) do
    ~H"""
    <li
      data-selected={"#{@selected}"}
      class={[
        "dark:data-[selected=true]:dark-sidebar-item-selected data-[selected=true]:border-primary data-[selected=true]:light-sidebar-item-selected h-nav-item hover:dark:dark-sidebar-item-hover hover:light-sidebar-item-hover flex items-center justify-center data-[selected=true]:border-r-2 lg:justify-start lg:px-4"
      ]}
    >
      <.link class="group text-base-300 flex size-full items-center justify-center gap-x-3 text-sm leading-[19px] font-light tracking-wide lg:justify-start" navigate={@path}>
        <span
          data-selected={"#{@selected}"}
          class={"size-5 #{@icon} data-[selected=false]:text-base-500 data-[selected=true]:text-primary"}
        />
        <span class={["hidden lg:inline", @selected && "text-base-50 font-semibold"]}>{@label}</span>
        <span :if={@badge} class="bg-base-800 ml-1 rounded-full px-1.5 py-0.5 text-xs">{@badge}</span>
      </.link>
    </li>
    """
  end
end
