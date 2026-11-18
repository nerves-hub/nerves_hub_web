defmodule NervesHubWeb.Live.Product.HealthProfiles do
  @moduledoc """
  A product's Device health settings: its health profiles, one at a time.

  A profile is edited as a whole and saved with one button. Every change
  (thresholds, periods, the operator, featuring, adding and removing
  metrics) stays on the page as a draft until then, and the page counts the
  unsaved changes. While there are some, the impact card shows what saving
  would do to the profile's devices: today's health from `device_health`,
  moved by the difference between previews of the saved and edited metrics
  (`HealthProfiles.preview_counts/5`), so stale health rows don't show up
  as changes.
  """
  use NervesHubWeb, :live_view

  import Number.Delimit, only: [number_to_delimited: 2]

  alias NervesHub.Devices.Metrics
  alias NervesHub.Firmwares
  alias NervesHub.Products
  alias NervesHub.Products.HealthProfileMetric
  alias NervesHub.Products.HealthProfiles
  alias NervesHubWeb.Components.Utils
  alias NervesHubWeb.Mounts.RequireEveryDevice

  on_mount(RequireEveryDevice)

  @default_period_seconds 3600

  @period_options [
    {"1 min", 60},
    {"5 min", 300},
    {"15 min", 900},
    {"30 min", 1800},
    {"1 h", 3600},
    {"2 h", 7200},
    {"6 h", 21_600},
    {"12 h", 43_200},
    {"24 h", 86_400}
  ]

  @decorate requires_membership()
  def mount(_params, _session, socket) do
    product = socket.assigns.current_scope.product

    socket
    |> assign(:page_title, "#{product.name} Health Profiles")
    |> sidebar_tab(:settings)
    |> assign(:product, product)
    |> assign(:custom_labels, Products.custom_health_metrics_labels(product))
    |> assign(:analytics?, Application.get_env(:nerves_hub, :analytics_enabled, false))
    |> assign_observed(product)
    |> assign_profiles()
    |> ok()
  end

  @decorate requires_membership()
  def handle_params(params, _uri, socket) do
    profiles = socket.assigns.profiles

    profile =
      Enum.find(profiles, &(to_string(&1.id) == params["profile"])) ||
        Enum.find(profiles, &is_nil(&1.platform)) ||
        hd(profiles)

    socket
    |> load_profile(profile)
    |> noreply()
  end

  # Every input on the page: thresholds and periods, and the metric picker,
  # which adds a row.
  @decorate requires_membership()
  def handle_event("edit", params, socket) do
    socket
    |> update(:draft, &merge_inputs(&1, params["metrics"] || %{}))
    |> add_picked(params["add_key"])
    |> draft_changed()
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("flip-operator", %{"index" => index}, socket) do
    socket
    |> update_row(index, fn row ->
      if row.built_in, do: row, else: %{row | operator: if(row.operator == :lte, do: :gte, else: :lte)}
    end)
    |> draft_changed()
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("toggle-featured", %{"index" => index}, socket) do
    socket
    |> update_row(index, fn row -> if row.built_in, do: row, else: %{row | featured: !row.featured} end)
    |> draft_changed()
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("use-suggested", %{"index" => index}, socket) do
    observed_stats = socket.assigns.observed_stats

    socket
    |> update_row(index, fn row ->
      case suggestion(observed_stats, row) do
        %{warning: warning, alert: alert} ->
          %{row | warning_threshold: Utils.format_number(warning), alert_threshold: Utils.format_number(alert)}

        nil ->
          row
      end
    end)
    |> draft_changed()
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("remove-metric", %{"index" => index}, socket) do
    index = String.to_integer(index)

    socket
    |> update(:draft, &List.delete_at(&1, index))
    |> update(:errors, &shift_errors(&1, index))
    |> draft_changed()
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("discard", _params, socket) do
    socket
    |> load_profile(socket.assigns.profile)
    |> noreply()
  end

  # On a phone the profiles are a select rather than a column of links.
  @decorate requires_membership()
  def handle_event("select-profile", %{"profile" => profile_id}, socket) do
    socket
    |> push_patch(to: profile_path(socket, profile_id))
    |> noreply()
  end

  @decorate requires_permission(:"product:update")
  def handle_event("save", params, socket) do
    draft = merge_inputs(socket.assigns.draft, params["metrics"] || %{})
    profile = socket.assigns.profile

    case HealthProfiles.save_metrics(profile, Enum.map(draft, &row_attrs/1)) do
      {:ok, saved} ->
        socket
        |> assign_profiles()
        |> load_profile(saved)
        |> put_flash(:info, "The #{profile_name(saved)} profile was saved.")
        |> noreply()

      {:error, index, changeset} ->
        socket
        |> assign(:draft, draft)
        |> assign(:errors, %{index => error_messages(changeset)})
        |> put_flash(:error, "The profile wasn't saved. Check #{row_name(Enum.at(draft, index))}.")
        |> noreply()
    end
  end

  @decorate requires_permission(:"product:update")
  def handle_event("create-platform-profile", %{"platform" => platform}, socket) when platform != "" do
    case HealthProfiles.create_platform_profile(socket.assigns.product, platform) do
      {:ok, profile} ->
        socket
        |> assign_profiles()
        |> put_flash(:info, "A health profile for #{profile.platform} was created, starting as a copy of Default.")
        |> push_patch(to: profile_path(socket, profile.id))
        |> noreply()

      {:error, changeset} ->
        socket
        |> put_flash(:error, "The profile wasn't created: #{changeset |> error_messages() |> Enum.join(" ")}")
        |> noreply()
    end
  end

  @decorate requires_permission(:"product:update")
  def handle_event("create-platform-profile", _no_platform, socket), do: {:noreply, socket}

  @decorate requires_permission(:"product:update")
  def handle_event("delete-profile", %{"profile_id" => profile_id}, socket) do
    profile = HealthProfiles.get_profile!(socket.assigns.product, profile_id)

    case HealthProfiles.delete_profile(profile) do
      {:ok, _} ->
        socket
        |> assign_profiles()
        |> put_flash(:info, "The #{profile.platform} profile was deleted. Its devices use Default again.")
        |> push_patch(to: profile_path(socket, nil))
        |> noreply()

      {:error, :cannot_delete_default} ->
        socket
        |> put_flash(:error, "The Default profile can't be deleted.")
        |> noreply()
    end
  end

  def handle_async(:saved_preview, {:ok, counts}, socket), do: {:noreply, assign(socket, :saved_preview, counts)}
  def handle_async(:saved_preview, {:exit, _reason}, socket), do: {:noreply, assign(socket, :saved_preview, nil)}

  def handle_async(:edited_preview, {:ok, counts}, socket), do: {:noreply, assign(socket, :edited_preview, counts)}
  def handle_async(:edited_preview, {:exit, _reason}, socket), do: {:noreply, assign(socket, :edited_preview, nil)}

  defp assign_profiles(socket) do
    %{product: product, current_scope: scope} = socket.assigns
    profiles = HealthProfiles.all_for_product(product)
    taken = profiles |> Enum.map(& &1.platform) |> Enum.reject(&is_nil/1)

    platforms =
      product
      |> Firmwares.get_unique_platforms()
      |> Enum.reject(&(is_nil(&1) or &1 in taken))
      |> Enum.sort()

    socket
    |> assign(:profiles, profiles)
    |> assign(:device_counts, HealthProfiles.device_counts(product, scope.user, profiles))
    |> assign(:available_platforms, platforms)
  end

  # Shows `profile` as saved, with no draft changes, and starts working out
  # what its saved metrics make of its devices, to compare edits against.
  defp load_profile(socket, profile) do
    %{product: product, current_scope: scope, profiles: profiles} = socket.assigns
    saved = Enum.map(profile.metrics, &row/1)

    socket =
      socket
      |> assign(:profile, profile)
      |> assign(:saved, saved)
      |> assign(:draft, saved)
      |> assign(:errors, %{})
      |> assign(:unsaved, 0)
      |> assign(:health_counts, HealthProfiles.health_counts(product, scope.user, profile, profiles))
      |> assign(:saved_preview, nil)
      |> assign(:edited_preview, nil)
      |> cancel_async(:edited_preview)

    if socket.assigns.analytics? do
      start_async(socket, :saved_preview, fn ->
        HealthProfiles.preview_counts(product, scope.user, profile, profiles, profile.metrics)
      end)
    else
      socket
    end
  end

  # After any change to the draft: recount the unsaved changes, and preview
  # the edited metrics when they all read as numbers.
  defp draft_changed(socket) do
    %{draft: draft, saved: saved} = socket.assigns
    unsaved = unsaved_changes(saved, draft)
    socket = assign(socket, :unsaved, unsaved)

    with true <- socket.assigns.analytics? and unsaved > 0,
         {:ok, metrics} <- draft_metrics(draft) do
      %{product: product, current_scope: scope, profile: profile, profiles: profiles} = socket.assigns

      socket
      |> assign(:edited_preview, nil)
      |> start_async(:edited_preview, fn ->
        HealthProfiles.preview_counts(product, scope.user, profile, profiles, metrics)
      end)
    else
      _nothing_to_preview ->
        socket
        |> cancel_async(:edited_preview)
        |> assign(:edited_preview, nil)
    end
  end

  # One draft row per metric. Thresholds are kept as typed, so a half-typed
  # number doesn't get rewritten under the cursor.
  defp row(%HealthProfileMetric{} = metric) do
    %{
      id: metric.id,
      key: metric.key,
      built_in: metric.built_in,
      featured: metric.featured,
      operator: metric.operator || :gte,
      warning_threshold: Utils.format_number(metric.warning_threshold),
      warning_period_seconds: metric.warning_period_seconds,
      alert_threshold: Utils.format_number(metric.alert_threshold),
      alert_period_seconds: metric.alert_period_seconds
    }
  end

  defp new_row(key, observed_stats) do
    built_in? = Map.has_key?(HealthProfiles.built_in_metrics(), key)

    row = %{
      id: nil,
      key: key,
      built_in: built_in?,
      featured: false,
      operator: :gte,
      warning_threshold: "",
      warning_period_seconds: @default_period_seconds,
      alert_threshold: "",
      alert_period_seconds: @default_period_seconds
    }

    cond do
      # A day of disconnects is the window that tells a flaky link from a
      # restart or two.
      built_in? ->
        %{
          row
          | warning_threshold: "3",
            alert_threshold: "10",
            warning_period_seconds: 86_400,
            alert_period_seconds: 86_400
        }

      suggestion = suggestion(observed_stats, row) ->
        %{
          row
          | warning_threshold: Utils.format_number(suggestion.warning),
            alert_threshold: Utils.format_number(suggestion.alert)
        }

      true ->
        row
    end
  end

  defp merge_inputs(draft, inputs) do
    draft
    |> Enum.with_index()
    |> Enum.map(fn {row, index} ->
      case inputs[Integer.to_string(index)] do
        %{} = input ->
          %{
            row
            | warning_threshold: Map.get(input, "warning_threshold", row.warning_threshold),
              alert_threshold: Map.get(input, "alert_threshold", row.alert_threshold),
              warning_period_seconds: period(input["warning_period_seconds"], row.warning_period_seconds),
              alert_period_seconds: period(input["alert_period_seconds"], row.alert_period_seconds)
          }

        _untouched ->
          row
      end
    end)
  end

  # A forged period that isn't a number keeps the row's; one out of range
  # goes through, for the changeset to refuse.
  defp period(nil, current), do: current

  defp period(value, current) do
    case Integer.parse(value) do
      {seconds, ""} -> seconds
      _not_a_number -> current
    end
  end

  defp add_picked(socket, key) when is_binary(key) and key != "" do
    key = String.trim(key)

    if Enum.any?(socket.assigns.draft, &(&1.key == key)) do
      socket
    else
      update(socket, :draft, &(&1 ++ [new_row(key, socket.assigns.observed_stats)]))
    end
  end

  defp add_picked(socket, _no_key), do: socket

  defp update_row(socket, index, fun) do
    update(socket, :draft, &List.update_at(&1, String.to_integer(index), fun))
  end

  # Errors are kept by row position, so removing a row moves the ones below
  # it up.
  defp shift_errors(errors, removed) do
    for {index, messages} <- errors, index != removed, into: %{} do
      {if(index > removed, do: index - 1, else: index), messages}
    end
  end

  # Each metric added, removed or changed is one change.
  defp unsaved_changes(saved, draft) do
    saved_by_id = Map.new(saved, &{&1.id, &1})
    draft_ids = draft |> Enum.map(& &1.id) |> Enum.reject(&is_nil/1) |> MapSet.new()

    changed =
      Enum.count(draft, fn row ->
        case saved_by_id[row.id] do
          nil -> true
          saved_row -> comparable(saved_row) != comparable(row)
        end
      end)

    removed = Enum.count(saved, &(not MapSet.member?(draft_ids, &1.id)))

    changed + removed
  end

  # "80" and "80.0" are the same threshold.
  defp comparable(row) do
    %{row | warning_threshold: parse_number(row.warning_threshold), alert_threshold: parse_number(row.alert_threshold)}
  end

  defp parse_number(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> number
      _not_a_number -> value
    end
  end

  # The draft as metrics the preview can judge, or :error while a threshold
  # doesn't read as a number.
  defp draft_metrics(draft) do
    Enum.reduce_while(draft, {:ok, []}, fn row, {:ok, acc} ->
      with warning when is_float(warning) <- parse_number(row.warning_threshold),
           alert when is_float(alert) <- parse_number(row.alert_threshold) do
        metric = %HealthProfileMetric{
          key: row.key,
          built_in: row.built_in,
          operator: row.operator,
          warning_threshold: warning,
          warning_period_seconds: row.warning_period_seconds,
          alert_threshold: alert,
          alert_period_seconds: row.alert_period_seconds
        }

        {:cont, {:ok, [metric | acc]}}
      else
        _not_a_number -> {:halt, :error}
      end
    end)
  end

  defp row_attrs(row) do
    %{
      "id" => row.id,
      "key" => row.key,
      "featured" => row.featured,
      "operator" => to_string(row.operator),
      "warning_threshold" => row.warning_threshold,
      "warning_period_seconds" => row.warning_period_seconds,
      "alert_threshold" => row.alert_threshold,
      "alert_period_seconds" => row.alert_period_seconds
    }
  end

  # The fleet's history for each metric key, for the median and p95 beside
  # each metric and the suggested thresholds. The picker offers every key
  # reported, padded with the well-known nerves_hub_health defaults so a
  # fresh product isn't looking at an empty list.
  defp assign_observed(socket, product) do
    observed_stats = if socket.assigns.analytics?, do: Metrics.observed_stats(product.id), else: %{}

    reported_keys =
      (Metrics.default_metrics() ++ Map.keys(observed_stats))
      |> Enum.uniq()
      |> Enum.sort()

    socket
    |> assign(:observed_stats, observed_stats)
    |> assign(:reported_keys, reported_keys)
  end

  # Suggested thresholds for the direction the row points, or nil when the
  # history can't support one (see HealthProfiles.suggested_thresholds/1).
  defp suggestion(_observed_stats, %{built_in: true}), do: nil

  defp suggestion(observed_stats, %{key: key, operator: operator}) do
    case HealthProfiles.suggested_thresholds(observed_stats[key]) do
      %{^operator => levels} -> levels
      nil -> nil
    end
  end

  # Offered only while the row's thresholds aren't already the suggestion.
  defp suggestion_to_offer(observed_stats, row) do
    case suggestion(observed_stats, row) do
      %{warning: warning, alert: alert} = suggestion ->
        if !(parse_number(row.warning_threshold) == warning and parse_number(row.alert_threshold) == alert),
          do: suggestion

      nil ->
        nil
    end
  end

  defp fleet_summary(observed_stats, key) do
    case observed_stats[key] do
      %{median: median, p95: p95} -> "fleet median #{Utils.nice_round(median)} · p95 #{Utils.nice_round(p95)}"
      _not_reported -> nil
    end
  end

  defp add_options(assigns) do
    taken = MapSet.new(assigns.draft, & &1.key)

    built_in =
      for {key, %{label: label}} <- Enum.sort(HealthProfiles.built_in_metrics()),
          not MapSet.member?(taken, key),
          do: {label, key}

    reported = for key <- assigns.reported_keys, not MapSet.member?(taken, key), do: {key, key}

    Enum.reject([{"Built-in", built_in}, {"Reported by devices", reported}], fn {_group, options} -> options == [] end)
  end

  defp period_options(seconds) do
    if List.keymember?(@period_options, seconds, 1),
      do: @period_options,
      else: @period_options ++ [{Utils.format_period(seconds), seconds}]
  end

  defp profile_path(socket, nil) do
    %{org: org, product: product} = socket.assigns.current_scope
    ~p"/org/#{org}/#{product}/settings/health"
  end

  defp profile_path(socket, profile_id) do
    %{org: org, product: product} = socket.assigns.current_scope
    ~p"/org/#{org}/#{product}/settings/health?#{[profile: profile_id]}"
  end

  defp profile_name(%{platform: nil}), do: "Default"
  defp profile_name(%{platform: platform}), do: platform

  defp row_name(%{built_in: true, key: key}), do: HealthProfiles.built_in_metrics()[key].label
  defp row_name(%{key: key}), do: key

  defp devices(1), do: "1 device"
  defp devices(count), do: "#{delimit(count)} devices"

  defp metrics(1), do: "1 metric"
  defp metrics(count), do: "#{count} metrics"

  defp delimit(count), do: number_to_delimited(count, precision: 0)

  defp changes(1), do: "1 unsaved change"
  defp changes(count), do: "#{count} unsaved changes"

  # The counts the impact card shows: today's, moved by what the edits would
  # change, once the preview has worked it out.
  defp shown_counts(assigns) do
    case deltas(assigns) do
      nil ->
        assigns.health_counts

      deltas ->
        Map.new(assigns.health_counts, fn {status, count} -> {status, max(count + deltas[status], 0)} end)
    end
  end

  defp deltas(%{unsaved: unsaved, saved_preview: %{} = saved, edited_preview: %{} = edited}) when unsaved > 0 do
    Map.new(saved, fn {status, count} -> {status, edited[status] - count} end)
  end

  defp deltas(_assigns), do: nil

  defp delta_label(nil, _status), do: nil

  defp delta_label(deltas, status) do
    case deltas[status] do
      delta when delta > 0 -> "+#{delimit(delta)}"
      delta when delta < 0 -> "−#{delimit(-delta)}"
      _none -> nil
    end
  end

  defp share(count, total) when total > 0, do: "width: #{count / total * 100}%"
  defp share(_count, _total), do: "width: 0%"

  defp error_messages(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
    end)
    |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field_name(field)} #{&1}.") end)
  end

  defp field_name(:warning_threshold), do: "Warning"
  defp field_name(:alert_threshold), do: "Unhealthy"
  defp field_name(:warning_period_seconds), do: "The warning period"
  defp field_name(:alert_period_seconds), do: "The unhealthy period"
  defp field_name(:key), do: "This metric"
  defp field_name(field), do: field |> to_string() |> String.replace("_", " ") |> String.capitalize()

  attr(:id, :string, required: true)
  attr(:class, :any, default: nil)
  attr(:platforms, :list, required: true)
  attr(:profiles, :list, required: true)

  # A profile is for a platform the product's firmware reports, picked from
  # those without one. With none left the button stays, disabled, saying why.
  defp add_platform_profile(assigns) do
    ~H"""
    <form id={@id} phx-change="create-platform-profile" class={["flex flex-col gap-2", @class]}>
      <%= if @platforms != [] do %>
        <.button type="label" class="relative w-full">
          <span class="lucide-plus" aria-hidden="true"></span>
          Add a platform profile
          <select name="platform" aria-label="Add a platform profile" class="absolute inset-0 cursor-pointer opacity-0">
            <option value="">Choose a platform</option>
            {Phoenix.HTML.Form.options_for_select(@platforms, nil)}
          </select>
        </.button>
      <% else %>
        <%!-- A disabled button swallows the hover, so it lets the hover through
             to its wrapper, which carries the reason. --%>
        <span
          title={
            if length(@profiles) > 1,
              do: "Every platform in this product's firmware has a profile.",
              else: "No firmware uploaded to this product reports a platform yet."
          }
          class="flex cursor-not-allowed"
        >
          <.button class="pointer-events-none w-full" disabled>
            <span class="lucide-plus" aria-hidden="true"></span> Add a platform profile
          </.button>
        </span>
      <% end %>
    </form>
    """
  end

  attr(:id_prefix, :string, required: true)
  attr(:shown, :map, required: true)
  attr(:deltas, :map, default: nil)

  defp impact_legend(assigns) do
    ~H"""
    <span :for={{status, label, dot} <- legend_entries(@shown)} id={"#{@id_prefix}-#{status}"} class="flex items-center gap-1.5">
      <span class={["size-1.5 rounded-full", dot]}></span>
      <span>{delimit(@shown[status])} {label}</span>
      <span :if={delta_label(@deltas, status)} class="font-medium text-warning-content">{delta_label(@deltas, status)}</span>
    </span>
    """
  end

  # Devices with no health yet are listed only when there are some.
  defp legend_entries(shown) do
    [
      {:healthy, "healthy", "bg-success"},
      {:warning, "warning", "bg-warning"},
      {:unhealthy, "unhealthy", "bg-alert"},
      {:unknown, "no data", "bg-line-strong"}
    ]
    |> Enum.reject(fn {status, _label, _dot} -> status == :unknown and shown.unknown == 0 end)
  end

  attr(:index, :integer, required: true)
  attr(:level, :string, required: true, values: ["warning", "alert"])
  attr(:row, :map, required: true)
  attr(:disabled, :boolean, required: true)

  # One level's threshold and period. The operator sits inside the threshold
  # field and flips on click: `≥` when high is unhealthy, `≤` when low is (a
  # frame rate goes bad low). Built-ins point one way only.
  defp level_fields(assigns) do
    ~H"""
    <div class="flex min-w-0 items-center gap-2">
      <span class="flex w-24 shrink-0 items-center gap-2 text-sm text-content-body @3xl:hidden">
        <span class={["size-1.5 rounded-full", if(@level == "warning", do: "bg-warning", else: "bg-alert")]}></span>
        {if @level == "warning", do: "Warning", else: "Unhealthy"}
      </span>
      <div class="flex h-8 w-20 shrink-0 items-center rounded border border-line-control bg-surface-raised focus-within:border-primary @max-3xl:h-9">
        <button
          :if={!@row.built_in}
          type="button"
          phx-click="flip-operator"
          phx-value-index={@index}
          disabled={@disabled}
          title={
            if @row.operator == :lte,
              do: "Unhealthy at or below the thresholds. Click to flip.",
              else: "Unhealthy at or above the thresholds. Click to flip."
          }
          class="flex h-full shrink-0 cursor-pointer items-center pl-2 font-mono text-xs text-content-faint hover:text-content-strong disabled:cursor-default disabled:hover:text-content-faint"
        >
          {if @row.operator == :lte, do: "≤", else: "≥"}
        </button>
        <span :if={@row.built_in} class="pl-2 font-mono text-xs text-content-faint" title="A count only goes bad high">≥</span>
        <input
          type="text"
          inputmode="decimal"
          name={"metrics[#{@index}][#{@level}_threshold]"}
          value={Map.fetch!(@row, :"#{@level}_threshold")}
          disabled={@disabled}
          phx-debounce="300"
          aria-label={"#{row_name(@row)} #{if @level == "warning", do: "warning", else: "unhealthy"} threshold"}
          class="size-full min-w-0 border-0 bg-transparent py-0 pr-2 pl-1.5 font-mono text-sm text-content-strong focus:ring-0 disabled:text-content-muted"
        />
      </div>
      <span class="shrink-0 text-ui text-content-faint">{if @row.built_in, do: "in", else: "for"}</span>
      <select
        name={"metrics[#{@index}][#{@level}_period_seconds]"}
        disabled={@disabled}
        aria-label={"#{row_name(@row)} #{if @level == "warning", do: "warning", else: "unhealthy"} period"}
        class="h-8 w-20 shrink-0 rounded border border-line-control bg-surface-raised py-0 pr-7 pl-2 font-mono text-sm text-content-strong focus:border-primary focus:ring-0 disabled:text-content-muted @max-3xl:h-9 @max-3xl:w-auto @max-3xl:flex-1"
      >
        {Phoenix.HTML.Form.options_for_select(period_options(Map.fetch!(@row, :"#{@level}_period_seconds")), Map.fetch!(@row, :"#{@level}_period_seconds"))}
      </select>
    </div>
    """
  end
end
