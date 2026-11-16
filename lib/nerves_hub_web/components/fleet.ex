defmodule NervesHubWeb.Components.Fleet do
  @moduledoc """
  How a set of products is doing, for the pages that sum up more than one:
  the organizations home page and an organization's Products tab.

  `load/1` fetches the health, deployment group, approval and failing update
  figures for a set of products at once. `attention_items/2` turns those into
  what needs someone's attention. The components here draw them, along with
  the online meter and health chip each product row carries.

  Both pages describe their organizations as entries shaped
  `%{org: org, role: role, products: [%{product: product, device_count: n}]}`.
  """
  use NervesHubWeb, :component

  import NervesHubWeb.Helpers.Authorization
  import Number.Delimit, only: [number_to_delimited: 2]

  alias NervesHub.Devices.Health
  alias NervesHub.Devices.Updates
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ManagedDeployments.Workflows

  @typedoc "How a set of products is doing, from `load/1`, keyed by product id."
  @type t() :: %{
          health: %{
            pos_integer() => %{healthy: non_neg_integer(), warning: non_neg_integer(), unhealthy: non_neg_integer()}
          },
          deployment_groups: %{pos_integer() => pos_integer()},
          approvals: [DeploymentWorkflowStep.t()],
          failing_updates: %{pos_integer() => %{count: pos_integer(), blocked_until: DateTime.t()}}
        }

  # What a product's health counts read as before any device has reported.
  @no_health %{healthy: 0, warning: 0, unhealthy: 0}

  @doc """
  The health, deployment group, approval and failing update figures for
  `product_ids`. Slower than the device totals, so pages load it after they
  first render.
  """
  @spec load([pos_integer()]) :: t()
  def load(product_ids) do
    %{
      health: Health.status_counts_by_product(product_ids),
      deployment_groups: ManagedDeployments.count_by_product(product_ids),
      approvals: Workflows.awaiting_approval_in_products(product_ids),
      failing_updates: Updates.failing_updates_by_product(product_ids)
    }
  end

  @doc """
  What needs someone's attention, in the order it's shown: releases waiting
  for approval, then unhealthy devices, then devices whose updates keep
  failing, each in the order its organization and product are listed.
  """
  @spec attention_items([map()], t()) :: [map()]
  def attention_items(orgs, fleet) do
    products =
      for entry <- orgs, %{product: product} <- entry.products, into: %{} do
        {product.id, {entry, product}}
      end

    approvals =
      for step <- fleet.approvals,
          {entry, product} <- [products[step.deployment_release.deployment_group.product_id]] do
        %{kind: :approval, entry: entry, product: product, step: step}
      end

    listed = for entry <- orgs, %{product: product} <- entry.products, do: {entry, product}

    unhealthy =
      for {entry, product} <- listed,
          %{unhealthy: count} when count > 0 <- [Map.get(fleet.health, product.id, @no_health)] do
        %{kind: :unhealthy, entry: entry, product: product, count: count}
      end

    failing =
      for {entry, product} <- listed,
          %{count: count, blocked_until: until} <- [fleet.failing_updates[product.id]] do
        %{kind: :failing_updates, entry: entry, product: product, count: count, until: until}
      end

    approvals ++ unhealthy ++ failing
  end

  @doc "An organization's initial, for the square that stands in for a logo."
  @spec monogram(String.t()) :: String.t()
  def monogram(name), do: name |> String.first() |> String.upcase()

  @doc "A count with thousands separators, or a dash while it loads."
  @spec delimited(integer() | nil) :: String.t()
  def delimited(nil), do: "—"
  def delimited(number), do: number_to_delimited(number, precision: 0)

  @doc ~S|A count and its noun: "1 device", "1,204 devices".|
  @spec count_noun(integer(), String.t(), String.t()) :: String.t()
  def count_noun(1, singular, _plural), do: "1 #{singular}"
  def count_noun(count, _singular, plural), do: "#{delimited(count)} #{plural}"

  @doc """
  `{connected, disconnected}` for a product, from per-organization counts
  keyed by organization id (`Accounts.get_org_device_counts/2`), or nil while
  its organization's counts load.
  """
  def product_online(online, org_id, product_id) do
    case online do
      %{^org_id => %{products: products}} -> Map.get(products, product_id, {0, 0})
      _ -> nil
    end
  end

  @doc "`{connected, disconnected}` for an organization, or nil while it loads."
  def org_online(online, org_id) do
    case online do
      %{^org_id => %{org: counts}} -> counts
      _ -> nil
    end
  end

  @doc "How much of `{connected, disconnected}` is online, as a whole percentage."
  def online_percent({connected, disconnected}) when connected + disconnected > 0,
    do: round(connected / (connected + disconnected) * 100)

  def online_percent(_), do: 0

  @doc "A product's health counts, or nil while the fleet figures load."
  def product_health(nil, _product_id), do: nil
  def product_health(fleet, product_id), do: Map.get(fleet.health, product_id, @no_health)

  @doc "An organization's health counts: the sum of its products'."
  def org_health(nil, _entry), do: nil

  def org_health(fleet, entry) do
    Enum.reduce(entry.products, @no_health, fn %{product: product}, acc ->
      Map.merge(acc, product_health(fleet, product.id), fn _status, a, b -> a + b end)
    end)
  end

  @doc "How many deployment groups a product has, or nil while the fleet figures load."
  def deployment_groups_count(nil, _product_id), do: nil
  def deployment_groups_count(fleet, product_id), do: Map.get(fleet.deployment_groups, product_id, 0)

  @doc ~S|A product's deployment groups as a subtitle: "No deployment groups", "3 deployment groups".|
  def deployment_groups_label(fleet, product_id) do
    case deployment_groups_count(fleet, product_id) do
      nil -> nil
      0 -> "No deployment groups"
      count -> count_noun(count, "deployment group", "deployment groups")
    end
  end

  @doc ~S|A span of seconds, rounded down to its largest unit: "5 minutes", "2 days".|
  @spec duration(integer()) :: String.t()
  def duration(seconds) when seconds < 3600, do: count_noun(max(div(seconds, 60), 1), "minute", "minutes")
  def duration(seconds) when seconds < 86_400, do: count_noun(div(seconds, 3600), "hour", "hours")
  def duration(seconds), do: count_noun(div(seconds, 86_400), "day", "days")

  # Where an attention row's product sits, as its subtitle names it: just the
  # product when there's one organization, otherwise the organization too.
  defp place(%{entry: entry, product: product}, single_org?) do
    if single_org?, do: product.name, else: "#{entry.org.name} / #{product.name}"
  end

  defp release_version(%DeploymentWorkflowStep{deployment_release: %{firmware: %{version: version}}}), do: version
  defp release_version(_step), do: nil

  defp resumes_in(%DateTime{} = until) do
    "updates resume in " <> duration(DateTime.diff(until, DateTime.utc_now()))
  end

  ## Components

  attr(:items, :list, required: true, doc: "from `attention_items/2`")
  attr(:single_org?, :boolean, required: true, doc: "name only the product in each row, not its organization too")

  @doc "The Needs attention section: a count and a row per item."
  def attention_section(assigns) do
    ~H"""
    <section id="needs-attention" aria-labelledby="attention-title" class="flex flex-col gap-2.5">
      <div class="flex items-center gap-2">
        <h2 id="attention-title" class="text-list-title text-content-strong">Needs attention</h2>
        <.badge tone="warning" count>{length(@items)}</.badge>
      </div>
      <div class="divide-y divide-line-subtle rounded-card border border-line-default bg-surface-raised shadow-card">
        <.attention_row :for={item <- @items} item={item} single_org?={@single_org?} />
      </div>
    </section>
    """
  end

  @doc "What stands in for the Needs attention section when nothing does."
  def all_clear(assigns) do
    ~H"""
    <div id="all-clear" class="flex items-center gap-3.5 rounded-card border border-line-default bg-surface-raised px-4 py-3.5 shadow-card">
      <span class="flex size-8 shrink-0 items-center justify-center rounded-md bg-success-soft text-success-content">
        <span class="lucide-check size-4" aria-hidden="true"></span>
      </span>
      <div class="flex flex-col gap-0.5">
        <p class="text-sm/4.5 font-medium text-content-strong">Nothing needs attention</p>
        <p class="text-xs text-content-muted">
          <.separated items={["No releases waiting for approval", "no unhealthy devices", "nothing in the penalty box"]} />
        </p>
      </div>
    </div>
    """
  end

  attr(:items, :list, required: true, doc: "the phrases, in order; a nil is left out")

  @doc ~S|Phrases run together with a middle dot between each, the dots a shade fainter than the text: "3 products · 1,204 devices".|
  def separated(assigns) do
    assigns = assign(assigns, :items, Enum.reject(assigns.items, &is_nil/1))

    ~H"""
    <%= for {item, index} <- Enum.with_index(@items) do %>
      <span :if={index > 0} class="text-content-faint">·</span>
      {item}
    <% end %>
    """
  end

  attr(:counts, :any, required: true, doc: "`{connected, disconnected}`, or nil while it loads")
  attr(:total, :integer, required: true)
  attr(:class, :any, default: "md:w-full md:max-w-45", doc: "the meter's width from md up; on a phone it fills the row")

  @doc "How many of a product's devices are online, as a count and a bar."
  def online_meter(%{total: 0} = assigns) do
    ~H"""
    <p class="text-ui/4 text-content-muted">No devices yet</p>
    """
  end

  # On a phone the count sits in a fixed slot to the left of the meter, so
  # meters line up from row to row; from md up the meter goes under it.
  def online_meter(assigns) do
    ~H"""
    <div class="flex items-center gap-3 md:block">
      <p class="min-w-36 shrink-0 text-ui/4 whitespace-nowrap text-content-muted tabular-nums md:min-w-0">
        <span class="online-count font-semibold text-content-strong">{delimited(@counts && elem(@counts, 0))}</span> of {delimited(@total)}<span class="md:hidden"> online</span>
      </p>
      <div class={["h-1 flex-1 overflow-hidden rounded-full bg-base-800 md:mt-1.75", @class]}>
        <div :if={@counts} class="h-full rounded-full bg-status-online" style={"width: #{online_percent(@counts)}%"}></div>
      </div>
    </div>
    """
  end

  attr(:health, :map, default: nil, doc: "the health counts, or nil while they load")
  attr(:size, :string, default: "sm", values: ~w(sm md), doc: "`sm` in a table row, `md` as a card's figure")

  @doc "The worst health a product's devices report, as a chip."
  def health_chip(%{health: nil} = assigns) do
    ~H"""
    <span class="text-sm text-content-faint">—</span>
    """
  end

  def health_chip(%{health: %{unhealthy: unhealthy}} = assigns) when unhealthy > 0 do
    ~H"""
    <.badge tone="alert" size={@size} dot>{@health.unhealthy} unhealthy</.badge>
    """
  end

  def health_chip(%{health: %{warning: warning}} = assigns) when warning > 0 do
    ~H"""
    <.badge tone="warning" size={@size} dot>{count_noun(@health.warning, "warning", "warnings")}</.badge>
    """
  end

  def health_chip(%{health: %{healthy: healthy}} = assigns) when healthy > 0 do
    ~H"""
    <.badge tone="success" size={@size} dot>Healthy</.badge>
    """
  end

  def health_chip(assigns) do
    ~H"""
    <span class="text-xs text-content-faint">Not reported</span>
    """
  end

  attr(:item, :map, required: true)
  attr(:single_org?, :boolean, required: true)

  # On a phone an attention row wraps its detail line instead of cutting it
  # off, and the approval's button goes under the text so the title keeps the
  # width. From md up each row is one line with the action at the end, in a
  # 128px slot so the actions line up from row to row.
  defp attention_row(%{item: %{kind: :approval}} = assigns) do
    ~H"""
    <div class="attention-item flex items-start gap-3 px-4 py-3.5 md:items-center md:gap-3.5">
      <.attention_icon icon="lucide-hourglass" class="bg-notice-soft text-notice-content" />
      <div class="flex min-w-0 flex-1 flex-col items-start gap-3 md:flex-row md:items-center md:gap-3.5">
        <div class="flex w-full min-w-0 flex-col gap-0.75 md:w-auto md:flex-1">
          <p class="text-sm/4.5 font-medium text-content-strong">
            <%= if version = release_version(@item.step) do %>
              Release <span class="font-mono text-ui">{version}</span> is waiting for approval
            <% else %>
              A release is waiting for approval
            <% end %>
          </p>
          <p class="text-xs text-content-muted md:truncate">
            <.separated items={[
              place(@item, @single_org?),
              @item.step.deployment_release.deployment_group.name,
              DeploymentWorkflowStep.label(@item.step)
            ]} />
          </p>
        </div>
        <div class="flex shrink-0 md:w-32 md:justify-end">
          <.button
            type="link"
            style={if authorized?(:"deployment_group:update", @item.entry.role), do: "primary", else: "secondary"}
            navigate={~p"/org/#{@item.entry.org}/#{@item.product}/deployment_groups/#{@item.step.deployment_release.deployment_group}"}
          >
            {if authorized?(:"deployment_group:update", @item.entry.role), do: "Review release", else: "View release"}
          </.button>
        </div>
      </div>
    </div>
    """
  end

  defp attention_row(%{item: %{kind: :unhealthy}} = assigns) do
    ~H"""
    <div class="attention-item relative flex items-start gap-3 px-4 py-3.5 md:items-center md:gap-3.5">
      <.attention_icon icon="lucide-activity" class="bg-alert-soft text-alert-content" />
      <div class="flex min-w-0 flex-1 flex-col gap-0.75">
        <p class="text-sm/4.5 font-medium text-content-strong">
          {if @item.count == 1, do: "1 device is unhealthy", else: "#{delimited(@item.count)} devices are unhealthy"}
        </p>
        <p class="text-xs text-content-muted md:truncate">{place(@item, @single_org?)}</p>
      </div>
      <.view_devices_link navigate={~p"/org/#{@item.entry.org}/#{@item.product}/devices?health_status=unhealthy"} />
    </div>
    """
  end

  defp attention_row(%{item: %{kind: :failing_updates}} = assigns) do
    ~H"""
    <div class="attention-item relative flex items-start gap-3 px-4 py-3.5 md:items-center md:gap-3.5">
      <.attention_icon icon="lucide-circle-pause" class="bg-warning-soft text-warning-content" />
      <div class="flex min-w-0 flex-1 flex-col gap-0.75">
        <p class="text-sm/4.5 font-medium text-content-strong">
          {if @item.count == 1,
            do: "1 device stopped taking updates after repeated failures",
            else: "#{delimited(@item.count)} devices stopped taking updates after repeated failures"}
        </p>
        <p class="text-xs text-content-muted md:truncate">
          <.separated items={[place(@item, @single_org?), resumes_in(@item.until)]} />
        </p>
      </div>
      <.view_devices_link navigate={~p"/org/#{@item.entry.org}/#{@item.product}/devices?updates=failed-updates"} />
    </div>
    """
  end

  attr(:icon, :string, required: true, doc: "the Lucide class, spelled out in full so Tailwind finds it")
  attr(:class, :any, required: true, doc: "the tile's tint and the icon's colour")

  defp attention_icon(assigns) do
    ~H"""
    <span class={["flex size-8 shrink-0 items-center justify-center rounded-md", @class]}>
      <span class={[@icon, "size-4"]} aria-hidden="true"></span>
    </span>
    """
  end

  attr(:navigate, :string, required: true)

  # Its ::after stretches over the whole row (the row is `relative`), so the
  # row is the tap target. On a phone only the chevron shows; the label stays
  # for screen readers.
  defp view_devices_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex h-8 shrink-0 items-center justify-end gap-1 text-ui/4 font-medium text-content-body after:absolute after:inset-0 hover:text-content-strong md:h-auto md:w-32"
    >
      <span class="sr-only md:not-sr-only">View devices</span>
      <span class="lucide-chevron-right size-4 text-content-faint md:size-3.5 md:text-content-muted" aria-hidden="true"></span>
    </.link>
    """
  end
end
