defmodule NervesHubWeb.Live.Product.Components do
  @moduledoc """
  What a product's devices are connected to, as each device last reported it:
  how many components are working and how many are missing, then every model
  by namespace, with how many there are, how many are missing, and the
  firmware they run.

  Read from Postgres alone (`NervesHub.Devices.Components`), once as the page
  mounts. Built from every device in the product, so a member who sees only
  some devices doesn't get it (`RequireEveryDevice`).

  Version 0.1.0 of the extension reports only whether a component is there,
  so the board's Updating and Behind their release figures, and errors and
  warnings in Needs attention, wait for later versions.
  """

  use NervesHubWeb, :live_view

  import NervesHubWeb.Components.Fleet, only: [delimited: 1, count_noun: 3]

  alias NervesHub.Devices.Components
  alias NervesHub.Devices.DeviceComponent
  alias NervesHubWeb.Components.DevicePage.ComponentsTab
  alias NervesHubWeb.Mounts.RequireEveryDevice

  on_mount(RequireEveryDevice)

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    product = scope.product

    socket
    |> assign(:product, product)
    |> assign(:page_title, "#{product.name} Components")
    |> sidebar_tab(:components)
    |> assign(:enabled?, product.extensions.components)
    |> assign(:counts, Components.product_counts(product))
    |> assign(:groups, product |> Components.models() |> group())
    |> ok()
  end

  # Models by namespace, namespaces in the order the docs list them and any
  # others after, alphabetically.
  @namespace_order ~w(mcu zigbee zwave ble usb custom)

  defp group(models) do
    models
    |> Enum.group_by(& &1.namespace)
    |> Enum.sort_by(fn {namespace, _} -> {Enum.find_index(@namespace_order, &(&1 == namespace)) || 99, namespace} end)
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <NervesHubWeb.Layouts.sidebar flash={@flash} current_scope={@current_scope} sidebar_tab={@sidebar_tab}>
      <:top_bar>
        <h1 class="text-card-title text-content-strong">Components</h1>
      </:top_bar>

      <div class="@container h-0 flex-1 overflow-y-auto overscroll-y-none">
        <div
          :if={!@enabled?}
          id="components-off"
          class="m-4 flex flex-col items-center gap-3 rounded-card border border-line-default bg-surface-raised px-6 py-14 text-center sm:m-6"
        >
          <span class="lucide-cpu size-7 text-content-muted" aria-hidden="true"></span>
          <h2 class="text-section-title text-content-strong">Components are off for {@product.name}</h2>
          <p class="max-w-lg text-sm text-content-muted">
            Turn them on and devices list what they're connected to: microcontrollers, Zigbee and Z-Wave nodes, USB peripherals.
          </p>
          <.link
            :if={authorized?(:"product:update", @current_scope)}
            navigate={~p"/org/#{@current_scope.org}/#{@product}/settings"}
            class="pt-1 text-ui font-medium text-notice-content hover:underline"
          >
            Turn on in Product settings
          </.link>
        </div>

        <div
          :if={@enabled? and @counts.components == 0}
          id="components-empty"
          class="m-4 flex flex-col items-center gap-2 rounded-card border border-line-default bg-surface-raised px-6 py-14 text-center sm:m-6"
        >
          <h2 class="text-section-title text-content-strong">No components yet</h2>
          <p class="max-w-lg text-sm text-content-muted">They show here once devices send their first components snapshot.</p>
        </div>

        <div :if={@enabled? and @counts.components > 0} class="flex flex-col gap-5 p-4 sm:p-6">
          <div class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
            <p class="text-ui text-content-body">What's connected to {@product.name}'s devices, as each device last reported it.</p>
            <p id="components-total" class="text-xs text-content-muted">
              {count_noun(@counts.components, "component", "components")} on {count_noun(@counts.devices, "device", "devices")}
            </p>
          </div>

          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div id="components-working" class="flex flex-col gap-1.5 rounded-card border border-line-default bg-surface-raised px-4 py-3.5">
              <span class="text-label font-semibold text-content-muted uppercase">Working</span>
              <span class="text-figure text-content-strong">{delimited(@counts.working)}</span>
              <span class="text-xs text-content-muted">{percent(@counts.working, @counts.components)} of components</span>
            </div>
            <div
              id="components-attention"
              class={[
                "flex flex-col gap-1.5 rounded-card border px-4 py-3.5",
                if(@counts.missing > 0, do: "border-alert/30 bg-alert-soft", else: "border-line-default bg-surface-raised")
              ]}
            >
              <span class={["flex items-center gap-1.5 text-label font-semibold uppercase", if(@counts.missing > 0, do: "text-alert-content", else: "text-content-muted")]}>
                <span :if={@counts.missing > 0} class="size-1.5 rounded-full bg-alert"></span> Need attention
              </span>
              <span class="text-figure text-content-strong">{delimited(@counts.missing)}</span>
              <span class="text-xs text-content-muted">{delimited(@counts.missing)} missing</span>
            </div>
          </div>

          <div id="components-models" class="flex flex-col overflow-clip rounded-card border border-line-default bg-surface-raised">
            <div class="flex h-11 items-center border-b border-line-default px-4">
              <h2 class="text-card-title text-content-strong">By model</h2>
            </div>
            <div class="flex h-9 items-center gap-4 border-b border-line-default bg-surface-muted px-4 text-label text-content-muted uppercase @max-3xl:hidden">
              <span class="grow">Model</span>
              <span class="w-37.5 shrink-0">On devices</span>
              <span class="w-55 shrink-0">Status</span>
              <span class="w-65 shrink-0">Firmware</span>
            </div>
            <section :for={{namespace, models} <- @groups}>
              <div class="flex h-8.5 items-center gap-2 border-b border-line-subtle bg-surface-muted px-4 text-xs">
                <span class="font-semibold text-content-strong">{ComponentsTab.namespace_label(namespace)}</span>
                <span class="font-mono text-2xs text-content-faint">{namespace}</span>
              </div>
              <div
                :for={model <- models}
                class="flex min-h-15 items-center gap-4 border-b border-line-subtle px-4 py-2.5 last:border-b-0 @max-3xl:flex-wrap @max-3xl:gap-y-3"
              >
                <div class="flex min-w-0 grow basis-0 flex-col gap-0.75 @max-3xl:basis-full">
                  <span class="truncate text-ui/4 font-medium text-content-strong">{DeviceComponent.model_label(model)}</span>
                  <span class="truncate font-mono text-xs text-content-muted">{model.vendor}:{model.model}</span>
                </div>
                <div class="flex w-37.5 shrink-0 flex-col gap-0.75">
                  <span class="font-mono text-ui/4 text-content-strong">{delimited(model.count)}</span>
                  <span class="text-xs text-content-muted">{spread(model)}</span>
                </div>
                <div class="flex w-55 shrink-0 flex-col gap-1.5">
                  <.bar segments={[{model.working, "bg-success"}, {model.missing, "bg-content-faint"}]} total={model.count} />
                  <span :if={model.missing == 0} class="text-xs text-content-muted">All working</span>
                  <span :if={model.missing > 0} class="text-xs">
                    <span class="text-content-body">{delimited(model.missing)} missing</span>
                    <span class="ml-1 text-content-muted">on {count_noun(model.missing_devices, "device", "devices")}</span>
                  </span>
                </div>
                <div class="flex w-65 shrink-0 flex-col gap-1.5">
                  <.bar segments={firmware_segments(model.firmware_versions)} total={model.count} />
                  <span class="truncate text-xs text-content-muted">
                    <.firmware_line versions={model.firmware_versions} total={model.count} />
                  </span>
                </div>
              </div>
            </section>
          </div>
        </div>
      </div>
    </NervesHubWeb.Layouts.sidebar>
    """
  end

  attr(:segments, :list, required: true, doc: "`{count, class}`, in order")
  attr(:total, :integer, required: true)

  defp bar(assigns) do
    ~H"""
    <div class="flex h-1.5 w-full gap-0.5 overflow-clip rounded-full bg-surface-muted" aria-hidden="true">
      <div :for={{count, class} <- @segments} :if={count > 0} class={["h-full shrink-0", class]} style={"width: #{count / @total * 100}%"}></div>
    </div>
    """
  end

  attr(:versions, :list, required: true)
  attr(:total, :integer, required: true)

  # The two most common versions with their share, then how many don't say.
  defp firmware_line(assigns) do
    {named, unnamed} = Enum.split_with(assigns.versions, fn {version, _count} -> version end)

    assigns =
      assigns
      |> assign(:named, Enum.take(named, 2))
      |> assign(:unnamed, Enum.sum_by(unnamed, &elem(&1, 1)))

    ~H"""
    <span :for={{{version, count}, index} <- Enum.with_index(@named)}>
      <span :if={index > 0} class="mx-1 text-content-faint">·</span>
      <span class="font-mono text-content-strong">{version}</span>
      <span :if={length(@named) > 1 or @unnamed > 0} class="ml-0.5">{percent(count, @total)}</span>
      <span :if={length(@named) == 1 and @unnamed == 0} class="ml-0.5">on all of them</span>
    </span>
    <span :if={@unnamed > 0}>
      <span :if={@named != []} class="mx-1 text-content-faint">·</span>{delimited(@unnamed)} don't say
    </span>
    """
  end

  # The most common version darkest, the next lighter, the rest and those
  # that don't say lightest.
  defp firmware_segments(versions) do
    {named, unnamed} = Enum.split_with(versions, fn {version, _count} -> version end)

    case named do
      [] ->
        []

      [{_, first}] ->
        [{first, "bg-content-strong"}]

      [{_, first}, {_, second} | rest] ->
        [
          {first, "bg-content-strong"},
          {second, "bg-content-faint"},
          {Enum.sum_by(rest, &elem(&1, 1)), "bg-line-strong"}
        ]
    end
    |> Kernel.++([{Enum.sum_by(unnamed, &elem(&1, 1)), "bg-line-default"}])
  end

  defp spread(%{count: count, devices: devices}) when count == devices,
    do: "one on #{if devices == 1, do: "1 device", else: "each of #{delimited(devices)} devices"}"

  defp spread(%{devices: devices}), do: "on #{count_noun(devices, "device", "devices")}"

  defp percent(_part, 0), do: "0%"

  defp percent(part, whole) do
    case part / whole * 100 do
      share when share >= 99.95 and part < whole -> "99.9%"
      share when share == trunc(share) -> "#{trunc(share)}%"
      share -> "#{:erlang.float_to_binary(share, decimals: 1) |> String.trim_trailing(".0")}%"
    end
  end
end
