defmodule NervesHubWeb.Components.DeviceFilters do
  @moduledoc """
  The devices list's Filters panel, and the applied filters shown as tokens
  under its query field.

  The panel is one form (`#filter-form`) that applies as it changes, like the
  query. Filters are grouped (Status, Firmware, Fleet, Alarms and metrics,
  More). A filter that takes several choices (`DeviceFiltering.multi_filters/0`)
  shows them as chips or a checklist, each with how many devices it would give
  alongside the other filters (`NervesHub.Devices.facet_counts/4`). Choices
  within a filter widen it; filters narrow each other.
  """

  use NervesHubWeb, :component

  alias NervesHub.Devices.AdvancedQuery
  alias NervesHub.Devices.DeviceFiltering
  alias NervesHubWeb.Components.CAHelpers
  alias Phoenix.LiveView.JS

  @default_filters DeviceFiltering.default_filters()

  # The filters the panel sets, and the Filters button counts. The state and
  # reason are tabs, the query has its own field, and the metric's operator and
  # value only narrow its key.
  @applicable Map.keys(@default_filters) --
                [:state, :reason, :advanced_query, :metrics_operator, :metrics_value]

  @chips %{
    health_status: [
      {"healthy", "Healthy", "bg-success"},
      {"warning", "Warning", "bg-warning"},
      {"unhealthy", "Unhealthy", "bg-alert"},
      {"unknown", "Unknown", "bg-status-offline"}
    ],
    connection: [
      {"connected", "Online", nil},
      {"offline", "Offline", nil},
      {"not_seen_in_seven_days", "Not seen 7 d+", nil},
      {"not_seen_in_fourteen_days", "Not seen 14 d+", nil},
      {"not_seen", "Never connected", nil}
    ],
    connection_type: [
      {"ethernet", "Ethernet", nil},
      {"wifi", "WiFi", nil},
      {"cellular", "Cellular", nil},
      {"unknown", "Unknown", nil}
    ],
    updates: [
      {"updating", "Updating", nil},
      {"failed-updates", "Failed", nil},
      {"penalty-box", "Penalty box", nil},
      {"disabled", "Disabled", nil}
    ],
    alarm_status: [
      {"with", "Any raised", nil},
      {"without", "None raised", nil}
    ],
    firmware_validation_status: [
      {"validated", "Validated", nil},
      {"not_validated", "Not validated", nil},
      {"unknown", "Unknown", nil}
    ]
  }

  @labels %{
    health_status: "Health",
    connection: "Connection",
    connection_type: "Network",
    firmware_version: "Version",
    updates: "Updates",
    deployment_id: "Deployment group",
    platform: "Platform",
    tags: "Tags",
    has_no_tags: "Untagged only",
    is_pinned: "Pinned only",
    alarm_status: "Alarms",
    alarm: "Alarm",
    metrics_key: "Metric",
    firmware_validation_status: "Firmware validation",
    signer_ca: "Signer CA",
    display_deleted: "Deleted devices",
    identifier: "Identifier",
    only_updating: "Updating",
    healthy: "Healthy",
    search: "Search"
  }

  @deleted [{"exclude", "Hide"}, {"include", "Include"}, {"only", "Only deleted"}]

  @doc "The filters the panel has applied: those not at their default."
  @spec applied(map()) :: [atom()]
  def applied(filters) do
    @applicable
    |> Enum.filter(fn key -> Map.get(filters, key) != Map.get(@default_filters, key) end)
    |> Enum.sort_by(&Enum.find_index(token_order(), fn k -> k == &1 end))
  end

  defp token_order() do
    [
      :identifier,
      :search,
      :health_status,
      :healthy,
      :connection,
      :connection_type,
      :firmware_version,
      :updates,
      :only_updating,
      :deployment_id,
      :platform,
      :tags,
      :has_no_tags,
      :is_pinned,
      :alarm_status,
      :alarm,
      :metrics_key,
      :firmware_validation_status,
      :signer_ca,
      :display_deleted
    ]
  end

  @doc "Whether `key` is a filter the panel sets, and so one a token can remove."
  @spec applicable?(atom()) :: boolean()
  def applicable?(key), do: key in @applicable

  @doc """
  The choices to count for each multi-choice filter the panel shows: its own,
  plus any chosen that it doesn't list (from an older link, say), so those
  still show and stay chosen.
  """
  @spec facets(map(), [String.t()], [String.t()]) :: %{atom() => [String.t()]}
  def facets(filters, firmware_versions, alarms) do
    listed =
      @chips
      |> Map.new(fn {key, chips} -> {key, Enum.map(chips, &elem(&1, 0))} end)
      |> Map.put(:firmware_version, firmware_versions ++ ["Unknown"])
      |> Map.put(:alarm, alarms)

    Map.new(listed, fn {key, values} ->
      {key, values ++ (DeviceFiltering.choices(Map.get(filters, key)) -- values)}
    end)
  end

  @doc """
  Turns the form's lists of choices (`health_status[]`) into the
  comma-separated value the filter takes.
  """
  @spec join_choices(map()) :: map()
  def join_choices(params) do
    Map.new(params, fn
      {key, values} when is_list(values) -> {key, values |> Enum.reject(&(&1 == "")) |> Enum.join(",")}
      pair -> pair
    end)
  end

  @doc "Shows the panel. It's rendered by the server, so this only pushes the event."
  def open(), do: JS.push("open-filters")

  defp close() do
    "close-filters"
    |> JS.push()
    |> JS.hide(
      to: "#filter-panel",
      transition: {"transition-transform duration-150 ease-in", "translate-x-0", "translate-x-full"},
      time: 150
    )
  end

  attr(:filters, :map, required: true)
  attr(:facets, :map, required: true, doc: "counts per filter and choice, from `NervesHub.Devices.facet_counts/4`")
  attr(:find, :string, default: "", doc: "what's typed in Find a filter")
  attr(:firmware_versions, :list, required: true)
  attr(:deployment_groups, :list, required: true)
  attr(:platforms, :list, required: true)
  attr(:alarms, :list, required: true)
  attr(:metrics_keys, :list, required: true)
  attr(:signer_cas, :list, required: true)
  attr(:total, :integer, default: nil, doc: "how many devices the filters give")
  attr(:product_total, :integer, default: nil, doc: "how many devices the product has")

  @doc "The Filters slide-over."
  def panel(assigns) do
    assigns =
      assigns
      |> assign(:applied, length(applied(assigns.filters)))
      |> assign(:facet_choices, facets(assigns.filters, assigns.firmware_versions, assigns.alarms))
      |> assign(:find, String.downcase(String.trim(assigns.find)))

    ~H"""
    <div class="fixed inset-0 z-50 bg-backdrop sm:hidden" phx-click={close()} aria-hidden="true"></div>
    <aside
      id="filter-panel"
      role="dialog"
      aria-labelledby="filter-panel-title"
      class={
        [
          "fixed top-(--topbar-height) right-0 bottom-0 z-50 flex w-95 max-w-full flex-col border-l border-line-default bg-surface-raised shadow-[-12px_0_32px_rgb(24_24_27/0.08),-1px_0_2px_rgb(24_24_27/0.04)]",
          # A sheet up from the bottom on a phone, leaving the top of the page in view.
          "max-sm:top-14 max-sm:left-0 max-sm:w-full max-sm:rounded-t-xl max-sm:border-t max-sm:border-l-0"
        ]
      }
      phx-mounted={JS.transition({"transition-transform duration-150 ease-out", "max-sm:translate-y-full sm:translate-x-full", "translate-x-0 translate-y-0"}, time: 150)}
      phx-window-keydown={close()}
      phx-key="escape"
    >
      <div class="mx-auto mt-2 h-1 w-9 shrink-0 rounded-full bg-line-strong sm:hidden" aria-hidden="true"></div>
      <header class="flex h-13 shrink-0 items-center justify-between border-b border-line-subtle pr-3 pl-5 max-sm:h-12 max-sm:border-b-0 max-sm:pl-4">
        <div class="flex items-baseline gap-2">
          <h2 id="filter-panel-title" class="text-list-title text-content-strong">Filters</h2>
          <span id="filters-applied" class="text-xs text-content-muted">{@applied} applied</span>
        </div>
        <div class="flex items-center gap-1.5">
          <kbd class="inline-flex items-center rounded-[3px] border border-line-default px-1.25 py-px font-sans text-[11px]/3.5 font-normal text-content-faint max-sm:hidden">
            esc
          </kbd>
          <button
            type="button"
            aria-label="Close filters"
            title="Close"
            phx-click={close()}
            class="flex size-7 shrink-0 cursor-pointer items-center justify-center rounded text-content-muted hover:bg-surface-muted hover:text-content-strong focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring"
          >
            <span class="lucide-x size-3.75" aria-hidden="true"></span>
          </button>
        </div>
      </header>

      <form id="filter-find" class="flex shrink-0 flex-col gap-2 px-5 pt-3 pb-1" phx-change="find-filter" phx-submit="find-filter">
        <label class="flex h-7.5 items-center gap-2 rounded border border-line-default bg-surface px-2.5 focus-within:border-primary">
          <span class="lucide-search size-3.25 text-content-faint" aria-hidden="true"></span>
          <span class="sr-only">Find a filter</span>
          <input
            type="search"
            name="find"
            value={@find}
            placeholder="Find a filter"
            autocomplete="off"
            phx-debounce="100"
            class="h-full min-w-0 flex-1 border-0 bg-transparent p-0 text-ui/4 text-content-body placeholder:text-content-faint focus:ring-0"
          />
        </label>
        <p class="text-xs text-content-muted">Counts show what each choice would give with your other filters.</p>
      </form>

      <form id="filter-form" class="min-h-0 flex-1 overflow-y-auto px-5 pt-1 pb-4" phx-change="update-filters" phx-submit="update-filters">
        <.group id="status" title="Status" summary="Health, connection, network" find={@find} filters={@filters} keys={[:health_status, :connection, :connection_type]} open>
          <:field terms={field_terms(:health_status)}>
            <.chips key={:health_status} filters={@filters} choices={@facet_choices} facets={@facets} />
          </:field>
          <:field terms={field_terms(:connection)}>
            <.chips key={:connection} filters={@filters} choices={@facet_choices} facets={@facets} />
          </:field>
          <:field terms={field_terms(:connection_type)}>
            <.chips key={:connection_type} filters={@filters} choices={@facet_choices} facets={@facets} />
          </:field>
        </.group>

        <.group id="firmware" title="Firmware" summary="Version, updates" find={@find} filters={@filters} keys={[:firmware_version, :updates]} open>
          <:field terms={field_terms(:firmware_version)}>
            <.checklist
              key={:firmware_version}
              filters={@filters}
              choices={@facet_choices}
              facets={@facets}
              bars
              hide_empty
              empty="No devices match the other filters."
            />
          </:field>
          <:field terms={field_terms(:updates)}>
            <.chips key={:updates} filters={@filters} choices={@facet_choices} facets={@facets} />
          </:field>
        </.group>

        <.group id="fleet" title="Fleet" summary="Group, platform, tags" find={@find} filters={@filters} keys={[:deployment_id, :platform, :tags, :has_no_tags, :is_pinned]} open>
          <:field terms={field_terms(:group_and_platform)}>
            <div class="flex gap-2.5">
              <.select
                key={:deployment_id}
                filters={@filters}
                options={[{"Any", ""}, {"No deployment group", "-1"} | Enum.map(@deployment_groups, &{&1.name, to_string(&1.id)})]}
              />
              <.select key={:platform} filters={@filters} options={[{"Any", ""} | Enum.map(@platforms, &{&1 || "Unknown", &1 || "Unknown"})]} />
            </div>
          </:field>
          <:field terms={field_terms(:tags)}>
            <div class="flex flex-col gap-2">
              <label for="filter-tags" class="text-ui/4 font-medium text-content-strong">Tags</label>
              <input
                type="text"
                id="filter-tags"
                name="tags"
                value={@filters.tags}
                placeholder="Every one of these tags, e.g. beta"
                autocomplete="off"
                phx-debounce="500"
                class={input_class()}
              />
              <div class="flex gap-4">
                <.toggle key={:has_no_tags} filters={@filters} />
                <.toggle key={:is_pinned} filters={@filters} />
              </div>
            </div>
          </:field>
        </.group>

        <.group
          id="alarms"
          title="Alarms and metrics"
          summary="Alarm, metric value"
          find={@find}
          filters={@filters}
          keys={[:alarm_status, :alarm, :metrics_key]}
        >
          <:field terms={field_terms(:alarms)}>
            <div class="flex flex-col gap-2">
              <.chips key={:alarm_status} filters={@filters} choices={@facet_choices} facets={@facets} />
              <.checklist :if={@facet_choices.alarm != []} key={:alarm} filters={@filters} choices={@facet_choices} facets={@facets} label="Raised alarm" />
            </div>
          </:field>
          <:field terms={field_terms(:metric)}>
            <div class="flex flex-col gap-2">
              <label for="filter-metrics_key" class="text-ui/4 font-medium text-content-strong">Metric</label>
              <div class="flex items-center gap-2">
                <select id="filter-metrics_key" name="metrics_key" class={[input_class(), "min-w-0 flex-1"]}>
                  {Phoenix.HTML.Form.options_for_select([{"Any", ""} | Enum.map(@metrics_keys, &{&1, &1})], @filters.metrics_key)}
                </select>
                <.radio_segments key={:metrics_operator} filters={@filters} label="Comparison" options={[{"gt", "Above"}, {"lt", "Below"}]} />
                <label for="filter-metrics_value" class="sr-only">Metric value</label>
                <input
                  type="number"
                  step="any"
                  id="filter-metrics_value"
                  name="metrics_value"
                  value={@filters.metrics_value}
                  placeholder="Value"
                  phx-debounce="300"
                  class={[input_class(), "w-20"]}
                />
              </div>
              <p class="text-xs text-content-muted">Last reported value. Applies once a value is entered.</p>
            </div>
          </:field>
        </.group>

        <.group
          id="more"
          title="More"
          summary="Validation, signer CA, deleted"
          find={@find}
          filters={@filters}
          keys={[:firmware_validation_status, :signer_ca, :display_deleted]}
          last
        >
          <:field terms={field_terms(:firmware_validation_status)}>
            <.chips key={:firmware_validation_status} filters={@filters} choices={@facet_choices} facets={@facets} />
          </:field>
          <:field terms={field_terms(:signer_ca)}>
            <.select
              key={:signer_ca}
              filters={@filters}
              options={
                [{"Any", ""} | Enum.map(@signer_cas, &{CAHelpers.label(&1), &1.serial})] ++
                  [{"No known CA", AdvancedQuery.Schema.not_set_value()}]
              }
            />
          </:field>
          <:field terms={field_terms(:display_deleted)}>
            <div class="flex flex-col gap-2">
              <span class="text-ui/4 font-medium text-content-strong">Deleted devices</span>
              <.radio_segments key={:display_deleted} filters={@filters} label="Deleted devices" options={deleted_options()} />
            </div>
          </:field>
        </.group>

        <p :if={nothing_found?(@find)} class="py-6 text-center text-ui/4.5 text-content-muted">
          No filter matches “{@find}”.
        </p>
      </form>

      <%!-- On a phone the sheet hides the list, so its button says how many
            devices closing it shows. --%>
      <footer class="flex h-15 shrink-0 items-center justify-between border-t border-line-subtle bg-surface px-5 max-sm:h-auto max-sm:gap-2 max-sm:px-4 max-sm:pt-3 max-sm:pb-[max(--spacing(3),env(safe-area-inset-bottom))]">
        <button
          type="button"
          phx-click="reset-filters"
          class="cursor-pointer text-ui/4 font-medium text-content-body hover:text-content-strong max-sm:h-11 max-sm:shrink-0 max-sm:rounded max-sm:border max-sm:border-line-control max-sm:bg-surface-raised max-sm:px-4 max-sm:text-sm"
        >
          Reset<span class="max-sm:hidden"> filters</span>
        </button>
        <div class="flex items-center gap-3 max-sm:flex-1">
          <span :if={@total} id="filters-total" class="text-xs text-content-muted max-sm:hidden">
            <span class="font-mono text-content-strong">{delimit(@total)}</span>
            <span :if={@product_total && @product_total != @total}> of <span class="font-mono">{delimit(@product_total)}</span></span>
            {if @total == 1 && @product_total in [nil, 1], do: "device", else: "devices"}
          </span>
          <.button type="button" style="primary" phx-click={close()} class="max-sm:h-11 max-sm:flex-1 max-sm:justify-center max-sm:text-sm">
            <span class="max-sm:hidden">Done</span>
            <span :if={@total} class="sm:hidden">Show <span class="font-mono">{delimit(@total)}</span> {if @total == 1, do: "device", else: "devices"}</span>
            <span :if={!@total} class="sm:hidden">Done</span>
          </.button>
        </div>
      </footer>
    </aside>
    """
  end

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:summary, :string, required: true)
  attr(:find, :string, required: true)
  attr(:filters, :map, required: true)
  attr(:keys, :list, required: true, doc: "the filters in the group, which open it when one is applied")
  attr(:open, :boolean, default: false)
  attr(:last, :boolean, default: false)

  slot(:field, required: true) do
    attr(:terms, :list, required: true, doc: "words Find a filter matches")
  end

  # A collapsible group of filters. It starts open when it's one of the first
  # three, has a filter applied, or something is typed in Find a filter. Its
  # toggle is client-side and survives patches.
  defp group(assigns) do
    assigns =
      assigns
      |> assign(:fields, Enum.filter(assigns.field, &matches?(&1.terms, assigns.find)))
      |> assign(
        :open,
        assigns.open || assigns.find != "" || Enum.any?(assigns.keys, &(&1 in applied(assigns.filters)))
      )

    ~H"""
    <section :if={@fields != []} id={"filter-group-#{@id}"} class={[!@last && "border-b border-line-subtle"]}>
      <button
        type="button"
        id={"filter-group-#{@id}-toggle"}
        aria-expanded={to_string(@open)}
        aria-controls={"filter-group-#{@id}-body"}
        class="flex w-full cursor-pointer items-center justify-between py-3.5"
        phx-click={toggle_group(@id)}
      >
        <span class="flex items-center gap-2">
          <span class="text-label text-content-muted uppercase">{@title}</span>
          <span id={"filter-group-#{@id}-summary"} class={["text-xs text-content-faint", @open && "hidden"]}>{@summary}</span>
        </span>
        <span id={"filter-group-#{@id}-chevron"} class={["lucide-chevron-down size-3 text-content-faint", @open && "rotate-180"]} aria-hidden="true"></span>
      </button>
      <div id={"filter-group-#{@id}-body"} class={["flex flex-col gap-3.5 pb-4.5", !@open && "hidden"]}>
        <div :for={field <- @fields}>{render_slot(field)}</div>
      </div>
    </section>
    """
  end

  defp toggle_group(id) do
    "hidden"
    |> JS.toggle_class(to: "#filter-group-#{id}-body")
    |> JS.toggle_class("hidden", to: "#filter-group-#{id}-summary")
    |> JS.toggle_class("rotate-180", to: "#filter-group-#{id}-chevron")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#filter-group-#{id}-toggle")
  end

  attr(:key, :atom, required: true)
  attr(:filters, :map, required: true)
  attr(:choices, :map, required: true)
  attr(:facets, :map, required: true)

  # A filter's choices as chips, any number of which can be on.
  defp chips(assigns) do
    assigns =
      assigns
      |> assign(:selected, DeviceFiltering.choices(Map.get(assigns.filters, assigns.key)))
      |> assign(:counts, Map.get(assigns.facets, assigns.key, %{}))
      |> assign(:chips, chips_for(assigns.key, assigns.choices[assigns.key]))

    ~H"""
    <fieldset id={"filter-#{@key}"} class="flex min-w-0 flex-col gap-2">
      <.legend key={@key} selected={@selected} />
      <input type="hidden" name={"#{@key}[]"} value="" />
      <div class="flex flex-wrap gap-1.5">
        <label
          :for={{value, label, dot} <- @chips}
          class={[
            "relative flex h-6.5 cursor-pointer items-center gap-1.5 rounded border border-line-default bg-surface-raised px-2 text-content-body hover:border-line-strong",
            "has-checked:border-primary has-checked:bg-notice-soft has-checked:text-notice-content",
            "has-focus-visible:outline-2 has-focus-visible:outline-offset-1 has-focus-visible:outline-focus-ring"
          ]}
        >
          <input type="checkbox" name={"#{@key}[]"} value={value} checked={value in @selected} class="peer sr-only" />
          <span class="lucide-check--bold hidden size-2.75 peer-checked:block" aria-hidden="true"></span>
          <.status_dot :if={dot} class={["size-1.5 peer-checked:hidden", dot]} />
          <span class="text-xs peer-checked:font-medium">{label}</span>
          <.count count={@counts[value]} />
        </label>
      </div>
    </fieldset>
    """
  end

  defp chips_for(key, values) do
    listed = Map.fetch!(@chips, key)

    Enum.map(values, fn value ->
      List.keyfind(listed, value, 0) || {value, value, nil}
    end)
  end

  attr(:key, :atom, required: true)
  attr(:filters, :map, required: true)
  attr(:choices, :map, required: true)
  attr(:facets, :map, required: true)
  attr(:label, :string, default: nil)
  attr(:bars, :boolean, default: false)
  attr(:hide_empty, :boolean, default: false, doc: "leave out a choice no device would give, unless it's chosen")
  attr(:empty, :string, default: nil, doc: "what to say when `hide_empty` leaves nothing")

  # A filter's choices as a list of checkboxes, for a list that can run long,
  # such as firmware versions. With `bars`, each has a bar for its share.
  defp checklist(assigns) do
    counts = Map.get(assigns.facets, assigns.key, %{})
    selected = DeviceFiltering.choices(Map.get(assigns.filters, assigns.key))

    assigns =
      assigns
      |> assign(:selected, selected)
      |> assign(:counts, counts)
      |> assign(:total, counts |> Map.values() |> Enum.sum())
      |> assign(:values, listed_choices(assigns.choices[assigns.key], counts, selected, assigns.hide_empty))

    ~H"""
    <fieldset id={"filter-#{@key}"} class="flex min-w-0 flex-col gap-1.5">
      <.legend key={@key} selected={@selected} label={@label} />
      <input type="hidden" name={"#{@key}[]"} value="" />
      <p :if={@values == [] && @empty} class="py-1 text-xs text-content-muted">{@empty}</p>
      <div class="flex flex-col gap-0.5">
        <label :for={value <- @values} class="group/choice flex h-6.5 cursor-pointer items-center gap-2.5">
          <input
            type="checkbox"
            name={"#{@key}[]"}
            value={value}
            checked={value in @selected}
            class="size-3.5 shrink-0 rounded-[3px] border-line-control bg-surface-raised checked:bg-primary focus:ring-0 focus:ring-offset-0 focus-visible:ring-2 focus-visible:ring-focus-ring"
          />
          <span
            title={value}
            class={[
              "min-w-0 truncate text-xs text-content-strong group-has-checked/choice:font-medium",
              if(@bars, do: "w-14 shrink-0", else: "flex-1"),
              if(value == "Unknown", do: "text-content-muted", else: "font-mono")
            ]}
          >
            {value}
          </span>
          <span :if={@bars} class="flex h-1 grow rounded-full bg-base-800">
            <span
              :if={@total > 0 && (@counts[value] || 0) > 0}
              class="h-1 rounded-full bg-line-control group-has-checked/choice:bg-primary"
              style={"width: #{Float.round(@counts[value] / @total * 100, 1)}%"}
            ></span>
          </span>
          <.count count={@counts[value]} class="w-7 shrink-0 text-right" />
        </label>
      </div>
    </fieldset>
    """
  end

  # Until the counts load, every choice shows.
  defp listed_choices(values, counts, _selected, hide_empty) when not hide_empty or counts == %{}, do: values

  defp listed_choices(values, counts, selected, true),
    do: Enum.filter(values, &(&1 in selected or Map.get(counts, &1, 0) > 0))

  attr(:key, :atom, required: true)
  attr(:selected, :list, required: true)
  attr(:label, :string, default: nil)

  # A filter's name, with a Clear link once something is chosen.
  defp legend(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <legend class="text-ui/4 font-medium text-content-strong">{@label || label(@key)}</legend>
      <button
        :if={@selected != []}
        type="button"
        phx-click="remove-filter"
        phx-value-key={@key}
        aria-label={"Clear #{label(@key)}"}
        class="cursor-pointer text-xs text-notice-content hover:underline"
      >
        Clear
      </button>
    </div>
    """
  end

  attr(:count, :integer, default: nil)
  attr(:class, :any, default: nil)

  defp count(assigns) do
    ~H"""
    <span
      :if={@count}
      class={[
        "font-mono text-label font-normal tracking-normal",
        if(@count == 0, do: "text-content-faint", else: "text-content-muted group-has-checked/choice:text-content-strong"),
        "peer-checked:text-notice-content",
        @class
      ]}
    >
      {delimit(@count)}
    </span>
    """
  end

  attr(:key, :atom, required: true)
  attr(:filters, :map, required: true)
  attr(:options, :list, required: true)

  defp select(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-1 basis-0 flex-col gap-2">
      <label for={"filter-#{@key}"} class="text-ui/4 font-medium text-content-strong">{label(@key)}</label>
      <select id={"filter-#{@key}"} name={@key} class={input_class()}>
        {Phoenix.HTML.Form.options_for_select(@options, to_string(Map.get(@filters, @key)))}
      </select>
    </div>
    """
  end

  attr(:key, :atom, required: true)
  attr(:filters, :map, required: true)

  # A filter that is on or off.
  defp toggle(assigns) do
    ~H"""
    <label class="flex cursor-pointer items-center gap-2 text-ui/4 text-content-body">
      <input type="hidden" name={@key} value="false" />
      <input
        type="checkbox"
        name={@key}
        value="true"
        checked={Map.get(@filters, @key) == true}
        class="size-3.5 rounded-[3px] border-line-control bg-surface-raised checked:bg-primary focus:ring-0 focus:ring-offset-0 focus-visible:ring-2 focus-visible:ring-focus-ring"
      />
      {label(@key)}
    </label>
    """
  end

  attr(:key, :atom, required: true)
  attr(:filters, :map, required: true)
  attr(:label, :string, required: true)
  attr(:options, :list, required: true)

  # One of a few options, as radio buttons drawn like a segmented control.
  defp radio_segments(assigns) do
    ~H"""
    <div id={"filter-#{@key}"} role="radiogroup" aria-label={@label} class="inline-flex shrink-0 gap-0.5 rounded-md border border-line-default bg-surface-muted p-0.5">
      <label
        :for={{value, label} <- @options}
        class={[
          "relative cursor-pointer rounded px-2.5 py-1.5 text-xs leading-none font-medium whitespace-nowrap text-content-muted hover:text-content-strong",
          "has-checked:bg-primary has-checked:text-primary-content has-checked:shadow-control light:has-checked:bg-indigo-600",
          "has-focus-visible:outline-2 has-focus-visible:outline-offset-1 has-focus-visible:outline-focus-ring"
        ]}
      >
        <input type="radio" name={@key} value={value} checked={Map.get(@filters, @key) == value} class="sr-only" />
        {label}
      </label>
    </div>
    """
  end

  defp input_class(),
    do:
      "h-7.5 rounded border border-line-control bg-surface-raised px-2.5 py-0 text-ui/4 text-content-body placeholder:text-content-faint focus:border-primary focus:ring-0"

  defp deleted_options(), do: @deleted

  attr(:filters, :map, required: true)
  attr(:deployment_groups, :list, required: true)
  attr(:signer_cas, :list, required: true)
  attr(:class, :any, default: nil)

  @doc """
  The applied filters as tokens, each removing its filter, and Clear all.
  Renders nothing when none are applied.
  """
  def tokens(assigns) do
    assigns = assign(assigns, :applied, applied(assigns.filters))

    ~H"""
    <div :if={@applied != []} id="filter-tokens" class={["flex shrink-0 flex-wrap items-center gap-1.5 px-6 pb-3", @class]}>
      <button
        :for={key <- @applied}
        type="button"
        id={"filter-token-#{key}"}
        phx-click="remove-filter"
        phx-value-key={key}
        aria-label={"Remove filter #{token_text(key, @filters, @deployment_groups, @signer_cas)}"}
        class="inline-flex h-6 max-w-80 cursor-pointer items-center gap-1 rounded border border-line-default bg-surface-raised pr-1 pl-2 font-mono text-xs text-content-body hover:border-line-strong"
      >
        <span class="truncate">{token_text(key, @filters, @deployment_groups, @signer_cas)}</span>
        <span class="lucide-x size-3 text-content-faint" aria-hidden="true"></span>
      </button>
      <button type="button" phx-click="reset-filters" class="ml-1 cursor-pointer text-xs text-notice-content hover:underline">
        Clear all
      </button>
    </div>
    """
  end

  @doc "A token's text for an applied filter, such as `health: unhealthy, warning`."
  @spec token_text(atom(), map(), list(), list()) :: String.t()
  def token_text(key, filters, deployment_groups, signer_cas)

  def token_text(:deployment_id, %{deployment_id: "-1"}, _groups, _cas), do: "group: none"

  def token_text(:deployment_id, %{deployment_id: id}, groups, _cas) do
    name = Enum.find_value(groups, id, &(to_string(&1.id) == id && &1.name))
    "group: #{name}"
  end

  def token_text(:signer_ca, %{signer_ca: serial}, _groups, cas) do
    if serial == AdvancedQuery.Schema.not_set_value() do
      "signer CA: none known"
    else
      "signer CA: #{Enum.find_value(cas, serial, &(&1.serial == serial && CAHelpers.label(&1)))}"
    end
  end

  def token_text(:metrics_key, filters, _groups, _cas) do
    case filters.metrics_value do
      "" -> "metric: #{filters.metrics_key}"
      value -> "#{filters.metrics_key} #{if filters.metrics_operator == "lt", do: "<", else: ">"} #{value}"
    end
  end

  def token_text(:has_no_tags, _filters, _groups, _cas), do: "untagged"
  def token_text(:is_pinned, _filters, _groups, _cas), do: "pinned"
  def token_text(:only_updating, _filters, _groups, _cas), do: "updating"

  def token_text(:display_deleted, %{display_deleted: value}, _groups, _cas),
    do: "deleted: #{@deleted |> List.keyfind(value, 0, {value, value}) |> elem(1) |> String.downcase()}"

  def token_text(key, filters, _groups, _cas) when is_map_key(@chips, key) do
    listed = Map.fetch!(@chips, key)

    choices =
      filters
      |> Map.get(key)
      |> DeviceFiltering.choices()
      |> Enum.sort_by(fn value -> Enum.find_index(listed, &(elem(&1, 0) == value)) || length(listed) end)
      |> Enum.map_join(", ", fn value ->
        case List.keyfind(listed, value, 0) do
          {_, label, _} -> String.downcase(label)
          nil -> value
        end
      end)

    "#{String.downcase(label(key))}: #{choices}"
  end

  def token_text(:firmware_version, filters, _groups, _cas),
    do: "firmware: #{filters.firmware_version |> DeviceFiltering.choices() |> Enum.join(", ")}"

  def token_text(key, filters, _groups, _cas), do: "#{String.downcase(label(key))}: #{Map.get(filters, key)}"

  defp label(key), do: Map.get(@labels, key, to_string(key))

  # The panel's fields, each with the words Find a filter matches.
  @field_ids [
    :health_status,
    :connection,
    :connection_type,
    :firmware_version,
    :updates,
    :group_and_platform,
    :tags,
    :alarms,
    :metric,
    :firmware_validation_status,
    :signer_ca,
    :display_deleted
  ]

  defp field_terms(:firmware_version), do: ["Firmware version"]
  defp field_terms(:group_and_platform), do: ["Deployment group", "Platform"]
  defp field_terms(:tags), do: ["Tags", "Untagged", "Pinned"]
  defp field_terms(:alarms), do: ["Alarm" | chip_labels(:alarm_status)]
  defp field_terms(:metric), do: ["Metric", "Value", "Above", "Below"]
  defp field_terms(:signer_ca), do: ["Signer CA", "Certificate"]
  defp field_terms(:display_deleted), do: ["Deleted devices" | Enum.map(@deleted, &elem(&1, 1))]
  defp field_terms(key), do: [label(key) | chip_labels(key)]

  defp chip_labels(key), do: @chips |> Map.get(key, []) |> Enum.map(&elem(&1, 1))

  defp matches?(_terms, ""), do: true
  defp matches?(terms, find), do: Enum.any?(terms, &String.contains?(String.downcase(&1), find))

  defp nothing_found?(""), do: false
  defp nothing_found?(find), do: not Enum.any?(@field_ids, &matches?(field_terms(&1), find))

  defp delimit(number), do: Number.Delimit.number_to_delimited(number, precision: 0)
end
