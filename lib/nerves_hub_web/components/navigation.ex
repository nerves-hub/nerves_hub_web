defmodule NervesHubWeb.Components.Navigation do
  use NervesHubWeb, :component

  alias NervesHub.Accounts.Scope
  alias NervesHub.ErrorReports
  alias NervesHub.ProductNotifications

  attr(:scope, Scope, required: false)
  attr(:selected_tab, :any)

  def sidebar(%{scope: %{product: product}} = assigns) do
    count =
      ProductNotifications.count(product)
      |> case do
        0 -> nil
        n -> n
      end

    unresolved_errors =
      if product.extensions.error_reports do
        case ErrorReports.status_counts(product) do
          %{unresolved: 0} -> nil
          %{unresolved: n} -> n
        end
      end

    assigns =
      assigns
      |> assign(:notifications_count, count)
      |> assign(:error_reports_enabled, product.extensions.error_reports)
      |> assign(:unresolved_errors_count, unresolved_errors)

    ~H"""
    <ul role="list">
      <.nav_link
        label="Insights"
        path={~p"/org/#{@scope.org}/#{@scope.product}/insights"}
        selected={:insights == @selected_tab}
        icon="data-[selected=false]:lucide-activity data-[selected=true]:lucide-activity--bold"
      />
      <.nav_link
        label="Devices"
        path={~p"/org/#{@scope.org}/#{@scope.product}/devices"}
        selected={:devices == @selected_tab}
        icon="data-[selected=false]:lucide-cpu data-[selected=true]:lucide-cpu--bold"
      />
      <.nav_link
        label="Deployment Groups"
        path={~p"/org/#{@scope.org}/#{@scope.product}/deployment_groups"}
        selected={:deployments == @selected_tab}
        icon="data-[selected=false]:lucide-rocket data-[selected=true]:lucide-rocket--bold"
      />
      <.nav_link
        label="Firmware"
        path={~p"/org/#{@scope.org}/#{@scope.product}/firmware"}
        selected={:firmware == @selected_tab}
        icon="data-[selected=false]:lucide-binary data-[selected=true]:lucide-binary--bold"
      />
      <.nav_link
        label="Archives"
        path={~p"/org/#{@scope.org}/#{@scope.product}/archives"}
        selected={:archives == @selected_tab}
        icon="data-[selected=false]:lucide-archive data-[selected=true]:lucide-archive--bold"
      />
      <.nav_link
        label="Support Scripts"
        path={~p"/org/#{@scope.org}/#{@scope.product}/scripts"}
        selected={:support_scripts == @selected_tab}
        icon="data-[selected=false]:lucide-file-code-corner data-[selected=true]:lucide-file-code-corner--bold"
      />
      <.nav_link
        :if={@error_reports_enabled}
        label="Errors"
        badge={@unresolved_errors_count}
        path={~p"/org/#{@scope.org}/#{@scope.product}/errors"}
        selected={:errors == @selected_tab}
        icon="data-[selected=false]:lucide-circle-exclamation-point data-[selected=true]:lucide-circle-exclamation-point--bold"
      />
      <.nav_link
        label="Notifications"
        badge={@notifications_count}
        path={~p"/org/#{@scope.org}/#{@scope.product}/notifications"}
        selected={:notifications == @selected_tab}
        icon="data-[selected=false]:lucide-bell data-[selected=true]:lucide-bell--bold"
      />
      <.nav_link
        label="Settings"
        path={~p"/org/#{@scope.org}/#{@scope.product}/settings"}
        selected={:settings == @selected_tab}
        icon="data-[selected=false]:lucide-settings data-[selected=true]:lucide-settings--bold"
      />
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
        "flex h-nav-item items-center justify-center hover:sidebar-item-hover data-[selected=true]:border-r-2 data-[selected=true]:border-primary data-[selected=true]:light-sidebar-item-selected max-sm:justify-start max-sm:px-4 lg:justify-start lg:px-4 dark:data-[selected=true]:dark-sidebar-item-selected collapsed:justify-center collapsed:px-0"
      ]}
    >
      <.link
        class="group flex size-full items-center justify-center gap-x-3 text-sm leading-[19px] font-light tracking-wide text-content-body max-sm:justify-start lg:justify-start collapsed:justify-center"
        navigate={@path}
      >
        <span
          data-selected={"#{@selected}"}
          class={"size-5 #{@icon} data-[selected=false]:text-content-faint data-[selected=true]:text-primary"}
        />
        <span data-label={@label} class={["reserve-semibold-width hidden max-sm:inline-flex max-sm:flex-col lg:inline-flex lg:flex-col collapsed:hidden", @selected && "font-semibold text-content-strong"]}>{@label}</span>
        <.badge :if={@badge} class="ml-1 collapsed:hidden">{@badge}</.badge>
      </.link>
    </li>
    """
  end
end
