defmodule NervesHubWeb.Components.DevicePage.Header do
  @moduledoc """
  The top of the device page: the identifier and its connection, the actions
  that act on the device, three facts about its firmware (what it runs, how it
  takes updates, and the group it belongs to), and the tabs.

  The page renders these itself rather than through the sidebar layout's
  `big_header` and `tabbed_nav` slots, which other pages share and which are a
  fixed height with wider tabs.
  """

  use NervesHubWeb, :component

  import NervesHubWeb.Helpers.Authorization

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.Updates
  alias NervesHub.Helpers.RelativeTime
  alias NervesHubWeb.Components.DeviceUpdateStatus
  alias NervesHubWeb.Components.UpdateProgress
  alias NervesHubWeb.Live.Devices.Show
  alias Phoenix.LiveView.JS

  attr(:device, Device, required: true)
  attr(:device_connection, :any, required: true)
  attr(:org, :any, required: true)
  attr(:product, :any, required: true)
  attr(:current_scope, :any, required: true)
  attr(:pinned?, :boolean, required: true)
  attr(:time_zone, :string, default: "UTC")
  attr(:firmware_update_stage, :any, default: nil)
  attr(:firmware_update_progress, :any, default: nil)
  attr(:inflight_version, :string, default: nil)

  attr(:end_tabs, :list,
    default: [],
    doc: "the tabs `tabs/1` puts at the right, which a phone reaches from the More sheet instead"
  )

  def render(assigns) do
    assigns = assign(assigns, :offline?, disconnected?(assigns.device_connection))

    ~H"""
    <div id="device-header" class="flex shrink-0 flex-col gap-3.5 px-4 pt-4 pb-5 sm:px-6 sm:pt-6 sm:pb-5.5">
      <div class="flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
        <div class="group/identifier flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1">
          <span
            data-connection-status={connection_status(@device_connection)}
            class={
              [
                # A 4px halo in every state: tinted green when online, neutral
                # otherwise (zinc-800 dark, zinc-100 light).
                "size-2.5 shrink-0 rounded-full ring-4",
                "data-[connection-status=connected]:bg-status-online data-[connection-status=connected]:ring-success-soft",
                "data-[connection-status=connecting]:animate-pulse data-[connection-status=connecting]:bg-status-connecting",
                "data-[connection-status=disconnected]:bg-status-offline data-[connection-status=unknown]:bg-status-offline",
                "not-data-[connection-status=connected]:ring-line-subtle light:not-data-[connection-status=connected]:ring-surface-muted"
              ]
            }
          />
          <h1 class="min-w-0 truncate font-mono text-[1.375rem]/7.5 font-semibold tracking-[-0.01em] text-content-strong">
            {@device.identifier}
          </h1>
          <button
            id="copy-device-identifier"
            type="button"
            phx-hook="CopyToClipboard"
            data-copy-value={@device.identifier}
            aria-label="Copy device identifier"
            title="Copy device identifier"
            class="flex size-7 shrink-0 cursor-pointer items-center justify-center rounded text-content-muted hover:bg-surface-muted hover:text-content-strong"
          >
            <span data-icon="copy" class="lucide-copy size-3.75"></span>
            <span data-icon="check" class="lucide-check hidden size-3.75 text-success"></span>
          </button>
          <%!-- On a phone the summary drops under the name, lined up with it. --%>
          <span class="flex max-sm:w-full max-sm:pl-5.5">
            <.connection_summary connection={@device_connection} />
          </span>
        </div>

        <%!-- A phone has the row of buttons under the facts instead. --%>
        <div class="flex shrink-0 items-center gap-2 max-sm:hidden">
          <.button :if={@pinned?} square aria-label="Unpin device" title="Unpin device" style="primary" phx-click="unpin">
            <.icon name="pinned" />
          </.button>
          <.button :if={!@pinned?} square aria-label="Pin device" title="Pin device" phx-click="pin">
            <.icon name="unpinned" />
          </.button>

          <%!-- One control, ordered by how much each action disturbs the
                device. The ellipsis on Reboot says a confirmation follows. --%>
          <div id="device-actions" class="flex h-8 overflow-hidden rounded border border-line-control bg-surface-raised shadow-xs">
            <.device_action event="identify" icon="identify" label="Identify" aria_label="Identify device" disabled={@offline?} />
            <.device_action event="reconnect" icon="connection" label="Reconnect" aria_label="Reconnect device" disabled={@offline?} />
            <.device_action
              event="reboot"
              icon="power"
              label="Reboot…"
              aria_label="Reboot device"
              confirm="Are you sure you want to reboot the device?"
              disabled={@offline?}
            />
          </div>
        </div>
      </div>

      <%!-- Side by side, or on a phone a row each, the label beside its value. --%>
      <div id="device-facts" class="flex flex-col border-y border-line-subtle sm:flex-row sm:flex-wrap sm:gap-x-7 sm:gap-y-3 sm:border-y-0 sm:pl-5.5">
        <.fact label="Firmware">
          <.firmware_fact
            device={@device}
            org={@org}
            product={@product}
            stage={@firmware_update_stage}
            progress={@firmware_update_progress}
            inflight_version={@inflight_version}
          />
        </.fact>

        <div class="hidden w-px self-stretch bg-line-default sm:block" />

        <.fact label="Updates">
          <.updates_fact device={@device} current_scope={@current_scope} time_zone={@time_zone} />
        </.fact>

        <div class="hidden w-px self-stretch bg-line-default sm:block" />

        <.fact label="Deployment group">
          <.link
            :if={@device.deployment_group}
            navigate={~p"/org/#{@org}/#{@product}/deployment_groups/#{@device.deployment_group}"}
            class="-mb-1 truncate pb-1 text-sm/4.5 font-medium text-content-strong underline decoration-line-strong underline-offset-4 hover:decoration-content-muted"
          >
            {@device.deployment_group.name}
          </.link>
          <span :if={!@device.deployment_group} class="text-sm/4.5 text-content-muted">None</span>
        </.fact>
      </div>

      <div id="device-actions-mobile" class="flex gap-2 sm:hidden">
        <.mobile_action event="identify" icon="identify" label="Identify" aria_label="Identify device" disabled={@offline?} class="flex-1" />
        <.mobile_action event="reconnect" icon="connection" label="Reconnect" aria_label="Reconnect device" disabled={@offline?} class="flex-1" />
        <.mobile_action
          icon="more"
          label="More"
          aria_label="More actions"
          aria-haspopup="dialog"
          aria-controls="device-more-sheet"
          phx-click={show_more_sheet()}
          class="w-22 shrink-0"
        />
      </div>

      <.more_sheet device={@device} org={@org} product={@product} pinned?={@pinned?} offline?={@offline?} end_tabs={@end_tabs} />
    </div>
    """
  end

  attr(:event, :string, default: nil)
  attr(:icon, :string, required: true)
  attr(:label, :string, required: true)
  attr(:aria_label, :string, required: true)
  attr(:disabled, :boolean, default: false)
  attr(:class, :any, default: nil)
  attr(:rest, :global, include: ~w(phx-click))

  # The buttons a phone shows under the facts, full height for a thumb.
  defp mobile_action(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      aria-label={@aria_label}
      disabled={@disabled}
      class={[
        "flex h-11 items-center justify-center gap-1.75 rounded-md border border-line-control bg-surface-raised text-sm/4.5 font-medium text-content-body shadow-xs",
        "enabled:cursor-pointer enabled:active:bg-surface-muted disabled:text-content-faint",
        @class
      ]}
      {@rest}
    >
      <.icon name={@icon} class="size-4 text-content-muted" />
      {@label}
    </button>
    """
  end

  attr(:device, Device, required: true)
  attr(:org, :any, required: true)
  attr(:product, :any, required: true)
  attr(:pinned?, :boolean, required: true)
  attr(:offline?, :boolean, required: true)
  attr(:end_tabs, :list, required: true)

  # What doesn't fit on a phone's header: the actions that don't need to be a
  # tap away, and the tabs that sit at the right on a wider screen. A sheet
  # from the bottom of the screen, over a scrim.
  defp more_sheet(assigns) do
    ~H"""
    <div
      id="device-more-sheet"
      role="dialog"
      aria-modal="true"
      aria-labelledby="device-more-sheet-title"
      class="fixed inset-0 z-50 sm:hidden"
      style="display: none"
      phx-window-keydown={hide_more_sheet()}
      phx-key="escape"
    >
      <div class="absolute inset-0 bg-backdrop" aria-hidden="true" phx-click={hide_more_sheet()}></div>
      <.focus_wrap
        id="device-more-sheet-panel"
        class="absolute inset-x-0 bottom-0 flex max-h-[85vh] flex-col overflow-y-auto rounded-t-2xl bg-surface-raised pb-[max(1.5rem,env(safe-area-inset-bottom))] shadow-overlay"
      >
        <div class="flex justify-center pt-2 pb-1" aria-hidden="true">
          <span class="h-1.25 w-9 rounded-full bg-line-strong"></span>
        </div>

        <div class="flex items-center justify-between gap-3 px-4 pt-2.5 pb-3.5">
          <div class="flex min-w-0 flex-col gap-0.5">
            <h2 id="device-more-sheet-title" class="truncate font-mono text-[0.9375rem]/5 font-semibold text-content-strong">{@device.identifier}</h2>
            <span class="truncate text-ui/4.5 text-content-muted">{@org.name} / {@product.name}</span>
          </div>
          <button
            type="button"
            aria-label="Close"
            phx-click={hide_more_sheet()}
            class="flex size-8 shrink-0 cursor-pointer items-center justify-center rounded-full bg-surface-muted text-content-muted"
          >
            <span class="lucide-x--bold size-3.5" aria-hidden="true"></span>
          </button>
        </div>

        <div class="px-4">
          <div class="flex flex-col overflow-clip rounded-xl border border-line-default">
            <.sheet_row
              icon={if @pinned?, do: "unpinned", else: "pinned"}
              label={if @pinned?, do: "Unpin device", else: "Pin device"}
              phx-click={JS.push(if(@pinned?, do: "unpin", else: "pin")) |> hide_more_sheet()}
            />
            <button
              id="copy-device-identifier-sheet"
              type="button"
              phx-hook="CopyToClipboard"
              data-copy-value={@device.identifier}
              class="flex h-row shrink-0 cursor-pointer items-center gap-3 border-t border-line-subtle px-4 text-left active:bg-surface-muted"
            >
              <span class="flex w-6 shrink-0 justify-center">
                <span data-icon="copy" class="lucide-copy size-4.5 text-content-muted" aria-hidden="true"></span>
                <span data-icon="check" class="lucide-check hidden size-4.5 text-success" aria-hidden="true"></span>
              </span>
              <span class="text-base/5 text-content-strong">Copy identifier</span>
            </button>
            <button
              type="button"
              disabled={@offline?}
              data-confirm="Are you sure you want to reboot the device?"
              phx-click={JS.push("reboot") |> hide_more_sheet()}
              class="group flex h-15 shrink-0 items-center gap-3 border-t border-line-subtle px-4 text-left enabled:cursor-pointer enabled:active:bg-surface-muted"
            >
              <span class="flex w-6 shrink-0 justify-center">
                <span class="lucide-power size-4.5 text-alert-content group-disabled:text-content-faint" aria-hidden="true"></span>
              </span>
              <span class="flex flex-col gap-0.5">
                <span class="text-base/5 font-medium text-alert-content group-disabled:text-content-faint">Reboot…</span>
                <span class="text-ui/4 text-content-muted">
                  {if @offline?, do: "Once the device is online", else: "You confirm on the next screen"}
                </span>
              </span>
            </button>
          </div>
        </div>

        <div :if={@end_tabs != []} class="flex flex-col gap-2 px-4 pt-5">
          <span class="px-1 text-label text-content-faint uppercase">Also on this device</span>
          <div class="flex flex-col overflow-clip rounded-xl border border-line-default">
            <.link
              :for={{key, label, path, _opts} <- @end_tabs}
              patch={path}
              phx-click={hide_more_sheet()}
              class="flex h-row shrink-0 items-center gap-3 border-t border-line-subtle pr-3 pl-4 first:border-t-0 active:bg-surface-muted"
            >
              <span class="flex w-6 shrink-0 justify-center">
                <span class={[end_tab_icon(key), "size-4.5 text-content-muted"]} aria-hidden="true"></span>
              </span>
              <span class="flex-1 text-base/5 text-content-strong">{label}</span>
              <span class="lucide-chevron-right size-4 text-content-faint" aria-hidden="true"></span>
            </.link>
          </div>
        </div>
      </.focus_wrap>
    </div>
    """
  end

  attr(:icon, :string, required: true)
  attr(:label, :string, required: true)
  attr(:rest, :global, include: ~w(phx-click))

  defp sheet_row(assigns) do
    ~H"""
    <button type="button" class="flex h-row shrink-0 cursor-pointer items-center gap-3 px-4 text-left active:bg-surface-muted" {@rest}>
      <span class="flex w-6 shrink-0 justify-center">
        <.icon name={@icon} class="size-4.5 text-content-muted" />
      </span>
      <span class="text-base/5 text-content-strong">{@label}</span>
    </button>
    """
  end

  defp end_tab_icon(:data_history), do: "lucide-chart-line"
  defp end_tab_icon(:settings), do: "lucide-settings"
  defp end_tab_icon(_tab), do: "lucide-chevron-right"

  defp show_more_sheet(js \\ %JS{}) do
    js
    |> JS.show(to: "#device-more-sheet", transition: {"ease-out duration-200", "opacity-0", "opacity-100"})
    |> JS.transition({"ease-out duration-200", "translate-y-full", "translate-y-0"}, to: "#device-more-sheet-panel")
    |> JS.focus_first(to: "#device-more-sheet-panel")
  end

  defp hide_more_sheet(js \\ %JS{}) do
    JS.hide(js, to: "#device-more-sheet", transition: {"ease-in duration-150", "opacity-100", "opacity-0"})
  end

  attr(:connection, :any, required: true)

  defp connection_summary(%{connection: %{status: :connected}} = assigns) do
    ~H"""
    <span class="flex shrink-0 items-baseline gap-1.25 pl-0.5 text-sm/4.5">
      <span class="font-medium text-success-content">Online</span>
      <span :if={@connection.established_at} class="text-content-muted">for {RelativeTime.elapsed(@connection.established_at)}</span>
    </span>
    """
  end

  defp connection_summary(%{connection: %{status: :connecting}} = assigns) do
    ~H"""
    <span class="shrink-0 pl-0.5 text-sm/4.5 font-medium text-content-muted">Connecting…</span>
    """
  end

  defp connection_summary(%{connection: %{status: :disconnected}} = assigns) do
    ~H"""
    <span class="flex shrink-0 items-baseline gap-1.25 pl-0.5 text-sm/4.5">
      <span class="font-medium text-content-muted">Offline</span>
      <span :if={last_seen(@connection)} class="text-content-muted">last seen {RelativeTime.from_now(last_seen(@connection))}</span>
    </span>
    """
  end

  defp connection_summary(assigns) do
    ~H"""
    <span class="shrink-0 pl-0.5 text-sm/4.5 text-content-muted">Never connected</span>
    """
  end

  attr(:event, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:label, :string, required: true)
  attr(:aria_label, :string, required: true)
  attr(:confirm, :string, default: nil)
  attr(:disabled, :boolean, default: false)

  defp device_action(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      aria-label={@aria_label}
      title={@aria_label}
      data-confirm={@confirm}
      disabled={@disabled}
      class="flex items-center gap-1.75 border-l border-line-default px-3 text-ui/4 font-medium text-content-body first:border-l-0 enabled:cursor-pointer enabled:hover:bg-surface-muted enabled:hover:text-content-strong disabled:text-content-faint"
    >
      <.icon name={@icon} class="size-3.75 text-content-muted" />
      <span class="hidden sm:inline">{@label}</span>
    </button>
    """
  end

  attr(:label, :string, required: true)
  slot(:inner_block, required: true)

  defp fact(assigns) do
    ~H"""
    <div class="flex min-h-11 min-w-0 items-center border-t border-line-subtle first:border-t-0 sm:min-h-0 sm:flex-col sm:items-start sm:gap-1 sm:border-t-0">
      <span class="w-35 shrink-0 text-label text-content-faint uppercase sm:w-auto">{@label}</span>
      <div class="flex min-w-0 flex-1 items-center py-2.5 sm:h-5.5 sm:max-w-full sm:flex-none sm:py-0">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr(:device, Device, required: true)
  attr(:org, :any, required: true)
  attr(:product, :any, required: true)
  attr(:stage, :any, required: true)
  attr(:progress, :any, required: true)
  attr(:inflight_version, :string, required: true)

  defp firmware_fact(%{device: %{firmware_metadata: nil}} = assigns) do
    ~H"""
    <span class="text-sm/4.5 text-content-muted">Unknown</span>
    """
  end

  defp firmware_fact(%{stage: stage, inflight_version: version} = assigns)
       when is_binary(version) and is_binary(stage) do
    firmware_fact_updating(assigns, UpdateProgress.updating?(stage))
  end

  defp firmware_fact(assigns), do: firmware_fact_updating(assigns, false)

  defp firmware_fact_updating(assigns, true) do
    ~H"""
    <span class="flex flex-wrap items-center gap-x-2 gap-y-1">
      <span class="font-mono text-ui/4 font-semibold text-content-strong">{@device.firmware_metadata.version}</span>
      <span class="lucide-arrow-right size-3.5 text-content-faint" aria-hidden="true"></span>
      <span class="font-mono text-ui/4 text-content-muted">{@inflight_version}</span>
      <.badge tone="notice">{UpdateProgress.short_phase(@stage, @progress)}</.badge>
    </span>
    """
  end

  defp firmware_fact_updating(assigns, false) do
    ~H"""
    <span class="flex flex-wrap items-center gap-x-2 gap-y-1">
      <.link
        navigate={~p"/org/#{@org}/#{@product}/firmware/#{@device.firmware_metadata.uuid}"}
        title="Open this firmware"
        class="flex items-center gap-2 hover:underline hover:decoration-line-strong hover:underline-offset-4"
      >
        <span class="font-mono text-ui/4 font-semibold text-content-strong">{@device.firmware_metadata.version}</span>
        <span class="font-mono text-ui/4 text-content-muted">{String.slice(@device.firmware_metadata.uuid, 0..7)}</span>
      </.link>
      <.badge :if={@device.firmware_auto_revert_detected} tone="alert" class="inline-flex items-center gap-1 pl-1.25">
        <span class="lucide-shield-exclamation-point size-3.25" aria-hidden="true"></span>Revert detected
      </.badge>
      <.badge :if={!@device.firmware_auto_revert_detected && @device.firmware_validation_status == :validated} tone="success" class="inline-flex items-center gap-1 pl-1.25">
        <span class="lucide-shield-check size-3.25" aria-hidden="true"></span>Validated
      </.badge>
      <.badge :if={!@device.firmware_auto_revert_detected && @device.firmware_validation_status == :not_validated} tone="alert" class="inline-flex items-center gap-1 pl-1.25">
        <span class="lucide-shield-exclamation-point size-3.25" aria-hidden="true"></span>Not validated
      </.badge>
    </span>
    """
  end

  attr(:device, Device, required: true)
  attr(:current_scope, :any, required: true)
  attr(:time_zone, :string, required: true)

  defp updates_fact(assigns) do
    ~H"""
    <%= if Updates.device_in_penalty_box?(@device) do %>
      <span class="flex items-center gap-1.5">
        <.tooltip id={"update-status-#{@device.id}"} placement="bottom">
          <span class="flex items-center gap-1.5 text-sm/4.5 font-medium text-warning-content">
            <span class="lucide-shield-exclamation-point size-3.5" aria-hidden="true"></span>Blocked
          </span>
          <:content>
            Updates blocked {DeviceUpdateStatus.friendly_blocked_until(@device.updates_blocked_until, @time_zone)}
          </:content>
        </.tooltip>
        <%!-- Dismissing the penalty box is a one-way action, not a state to
              switch between, so it reads as a button rather than a toggle. --%>
        <button
          type="button"
          phx-click="clear-penalty-box"
          aria-label="Clear the penalty box"
          title="Clear the penalty box"
          disabled={!authorized?(:"device:clear-penalty-box", @current_scope)}
          class="flex items-center rounded p-0.5 text-content-muted hover:bg-surface-muted hover:text-content-strong disabled:pointer-events-none disabled:opacity-60"
        >
          <span class="lucide-x size-3.5" />
        </button>
      </span>
    <% else %>
      <div class="relative">
        <button
          type="button"
          id="update-mode-toggle"
          phx-click={toggle_update_mode_menu()}
          aria-haspopup="menu"
          aria-label={"Firmware updates: #{Show.update_mode_label(@device.update_mode)}"}
          disabled={!authorized?(:"device:toggle-updates", @current_scope)}
          class="-mx-1 flex h-5.5 cursor-pointer items-center gap-1.5 rounded px-1 hover:bg-surface-muted disabled:cursor-default disabled:hover:bg-transparent"
        >
          <span class={[Show.update_mode_icon(@device.update_mode), update_mode_fact_color(@device.update_mode), "size-3.5"]} />
          <span class="text-sm/4.5 font-medium text-content-strong">{Show.update_mode_label(@device.update_mode)}</span>
          <span class="lucide-chevron-down size-3.5 text-content-faint" />
        </button>

        <div
          id="update-mode-menu-container"
          class="hidden"
          phx-click-away={hide_update_mode_menu()}
          phx-window-keydown={hide_update_mode_menu()}
          phx-key="escape"
        >
          <div
            id="update-mode-menu"
            role="menu"
            class="absolute top-7 left-0 z-30 flex w-80 flex-col rounded-md border border-line-default bg-surface-overlay p-2 shadow-overlay"
          >
            <button
              :for={{mode, label, description} <- Show.update_modes()}
              type="button"
              role="menuitem"
              phx-click={JS.push("set-update-mode", value: %{mode: mode}) |> hide_update_mode_menu()}
              class="flex cursor-pointer items-start gap-2.5 rounded p-2 text-left hover:bg-surface-muted"
            >
              <span class={[Show.update_mode_icon(mode), Show.update_mode_color(mode), "mt-0.5 size-5 shrink-0"]} />
              <span class="flex flex-col gap-0.5">
                <span class="flex items-center gap-1.5 text-sm font-medium text-content-strong">
                  {label}
                  <span :if={@device.update_mode == mode} class="lucide-check size-4 text-primary" />
                </span>
                <span class="text-xs/snug text-content-muted">{description}</span>
              </span>
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  The device page's tabs: the main ones from the left, and Data History and
  Settings, which are about the device rather than what it is doing, from the
  right.
  """
  attr(:tabs, :list,
    required: true,
    doc: "`{key, label, path, opts}` for each tab, opts holding `:dimmed`, `:dot` and `:count`"
  )

  attr(:end_tabs, :list, required: true)
  attr(:selected, :atom, required: true)

  def tabs(assigns) do
    ~H"""
    <div class="relative shrink-0">
      <nav
        id="device-tabs"
        phx-hook="ActiveTabInView"
        aria-label="Device"
        class="peer flex w-full shrink-0 justify-between gap-6 overflow-x-auto border-b border-line-rule px-1 [scrollbar-width:none] sm:px-3"
      >
        <div class="flex shrink-0">
          <.tab :for={tab <- @tabs} tab={tab} selected={@selected} />
        </div>
        <%!-- A phone reaches these from the More sheet, unless one is open. --%>
        <div class="flex shrink-0">
          <.tab :for={{key, _label, _path, _opts} = tab <- @end_tabs} tab={tab} selected={@selected} class={key != @selected && "max-sm:hidden"} />
        </div>
      </nav>
      <%!-- On a phone the strip scrolls, and fades at its right edge while there's
            more of it. A mask would fade the strip's rule too. ActiveTabInView
            keeps the selected tab in view and marks the strip's end. --%>
      <div
        class="pointer-events-none absolute top-0 right-0 bottom-px w-14 bg-linear-to-r from-transparent to-surface to-75% peer-data-scrolled-to-end:hidden sm:hidden"
        aria-hidden="true"
      >
      </div>
    </div>
    """
  end

  attr(:tab, :any, required: true)
  attr(:selected, :atom, required: true)
  attr(:class, :any, default: nil)

  defp tab(%{tab: {key, label, path, opts}} = assigns) do
    assigns = assign(assigns, key: key, label: label, path: path, opts: opts)

    ~H"""
    <.link
      patch={@path}
      aria-current={if @key == @selected, do: "page"}
      data-dimmed={@opts[:dimmed]}
      class={[
        "group relative flex h-11 shrink-0 items-center gap-1.5 px-3 text-sm/5 whitespace-nowrap text-content-muted",
        "hover:text-content-strong aria-[current=page]:font-medium aria-[current=page]:text-content-strong",
        "data-dimmed:text-content-faint",
        @class
      ]}
    >
      {@label}
      <span :if={@opts[:dot]} class="size-1.5 rounded-full bg-warning" aria-label="Needs attention"></span>
      <.badge :if={@opts[:count]} count>{@opts[:count]}</.badge>
      <%!-- The selected tab's bar, which a hovered tab previews in grey. --%>
      <span class="absolute inset-x-3 -bottom-px hidden h-0.5 rounded-[1px] bg-line-strong group-hover:block group-aria-[current=page]:block group-aria-[current=page]:bg-primary"></span>
    </.link>
    """
  end

  defp connection_status(%{status: status}) when status in [:connected, :connecting, :disconnected],
    do: to_string(status)

  defp connection_status(_connection), do: "unknown"

  defp last_seen(connection), do: connection.last_seen_at || connection.disconnected_at

  defp disconnected?(connection), do: is_nil(connection) || connection.status != :connected

  # The menu's icons carry each mode's colour; in the fact strip only
  # Automatic does, so a quiet mode doesn't read as a warning.
  defp update_mode_fact_color(:automatic), do: "text-success-content"
  defp update_mode_fact_color(:off), do: "text-alert-content"
  defp update_mode_fact_color(_mode), do: "text-content-muted"

  defp toggle_update_mode_menu(js \\ %JS{}) do
    JS.toggle(js,
      to: "#update-mode-menu-container",
      in: {"ease-out duration-150", "opacity-0", "opacity-100"},
      out: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end

  # Only ever closes, so Escape and click-away cannot open it the way JS.toggle
  # would, and are no-ops when it is already closed.
  defp hide_update_mode_menu(js \\ %JS{}) do
    JS.hide(js,
      to: "#update-mode-menu-container",
      transition: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end
end
