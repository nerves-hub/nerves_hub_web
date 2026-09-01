defmodule NervesHubWeb.Live.Product.HealthProfiles do
  use NervesHubWeb, :live_view

  alias NervesHub.Devices.Metrics
  alias NervesHub.Firmwares
  alias NervesHub.Products
  alias NervesHub.Products.HealthProfiles
  alias NervesHubWeb.Components.DeviceHealth.MetricLabels

  def mount(_params, _session, socket) do
    product = socket.assigns.current_scope.product

    socket
    |> assign(:page_title, "#{product.name} Health Profiles")
    |> sidebar_tab(:settings)
    |> assign(:product, product)
    |> assign(:custom_labels, Products.custom_health_metrics_labels(product))
    |> assign(:reported_keys, reported_keys(product))
    |> assign_profiles()
    |> ok()
  end

  # Flipping the operator is page state until the row is saved: the flipped
  # thresholds usually need adjusting before they validate, so nothing is
  # persisted on the click itself.
  def handle_event("flip-operator", %{"target" => target, "operator" => current}, socket) do
    flipped = if current == "gte", do: "lte", else: "gte"

    {:noreply, update(socket, :pending_operators, &Map.put(&1, target, flipped))}
  end

  def handle_event("create-platform-profile", %{"platform" => platform}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    case HealthProfiles.create_platform_profile(socket.assigns.product, platform) do
      {:ok, profile} ->
        socket
        |> assign_profiles()
        |> put_flash(:info, "A health profile for #{profile.platform} was created, seeded from the default profile.")
        |> noreply()

      {:error, changeset} ->
        socket
        |> put_flash(:error, "Could not create the profile: #{first_error(changeset)}")
        |> noreply()
    end
  end

  def handle_event("delete-profile", %{"profile_id" => profile_id}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    profile = HealthProfiles.get_profile!(socket.assigns.product, profile_id)

    case HealthProfiles.delete_profile(profile) do
      {:ok, _} ->
        socket
        |> assign_profiles()
        |> put_flash(
          :info,
          "The #{profile.platform} health profile was deleted. Its devices use the default profile again."
        )
        |> noreply()

      {:error, :cannot_delete_default} ->
        socket
        |> put_flash(:error, "The default health profile cannot be deleted.")
        |> noreply()
    end
  end

  def handle_event("add-metric", %{"profile_id" => profile_id, "metric" => attrs}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    profile = HealthProfiles.get_profile!(socket.assigns.product, profile_id)

    case HealthProfiles.add_metric(profile, normalize_periods(attrs)) do
      {:ok, metric} ->
        socket
        |> assign_profiles()
        |> put_flash(:info, "#{metric.key} was added to the profile.")
        |> noreply()

      {:error, changeset} ->
        socket
        |> put_flash(:error, "Could not add the metric: #{first_error(changeset)}")
        |> noreply()
    end
  end

  def handle_event("update-metric", %{"profile_id" => profile_id, "metric_id" => metric_id, "metric" => attrs}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    profile = HealthProfiles.get_profile!(socket.assigns.product, profile_id)
    metric = HealthProfiles.get_metric!(profile, metric_id)

    case HealthProfiles.update_metric(metric, normalize_periods(attrs)) do
      {:ok, metric} ->
        socket
        |> assign_profiles()
        |> put_flash(:info, "#{metric.key} was updated.")
        |> noreply()

      {:error, changeset} ->
        socket
        |> put_flash(:error, "Could not update the metric: #{first_error(changeset)}")
        |> noreply()
    end
  end

  def handle_event("delete-metric", %{"profile_id" => profile_id, "metric_id" => metric_id}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    profile = HealthProfiles.get_profile!(socket.assigns.product, profile_id)
    metric = HealthProfiles.get_metric!(profile, metric_id)

    :ok = HealthProfiles.delete_metric(metric)

    socket
    |> assign_profiles()
    |> put_flash(:info, "#{metric.key} no longer affects health for this profile.")
    |> noreply()
  end

  defp assign_profiles(socket) do
    profiles = HealthProfiles.all_for_product(socket.assigns.product)

    taken = profiles |> Enum.map(& &1.platform) |> Enum.reject(&is_nil/1)

    platforms =
      socket.assigns.product
      |> Firmwares.get_unique_platforms()
      |> Enum.reject(&(is_nil(&1) or &1 in taken))
      |> Enum.sort()

    socket
    |> assign(:profiles, profiles)
    |> assign(:available_platforms, platforms)
    |> assign(:pending_operators, %{})
  end

  # Keys offered in the metric picker: everything devices of this product have
  # reported, padded with the well-known nerves_hub_health defaults so a fresh
  # product isn't looking at an empty list.
  defp reported_keys(product) do
    (Metrics.default_metrics() ++ Metrics.distinct_keys(product.id))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp metric_options(assigns, profile) do
    taken = MapSet.new(profile.metrics, & &1.key)

    built_in =
      for {key, %{label: label}} <- Enum.sort(HealthProfiles.built_in_metrics()),
          key not in taken,
          do: {label, key}

    regular =
      for key <- assigns.reported_keys,
          not MapSet.member?(taken, key),
          do: {metric_label(assigns, key), key}

    [{"Built-in", built_in}, {"Health metrics", regular}]
  end

  # Built-ins carry their own label; everything else derives its label the
  # same way the device health page does.
  defp metric_label(assigns, key) do
    case HealthProfiles.built_in_metrics() do
      %{^key => %{label: label}} -> label
      _ -> MetricLabels.label(key, assigns.custom_labels)
    end
  end

  # The operator sits between the metric and its thresholds and flips on
  # click: `>=` when high is unhealthy, `<=` when low is (a frame rate goes
  # bad low).
  attr(:target, :string, required: true)
  attr(:operator, :any, required: true)
  attr(:disabled, :boolean, default: false)

  defp operator_flip(assigns) do
    ~H"""
    <input type="hidden" name="metric[operator]" value={to_string(@operator)} />
    <button
      type="button"
      phx-click="flip-operator"
      phx-value-target={@target}
      phx-value-operator={to_string(@operator)}
      title={operator_title(@operator)}
      disabled={@disabled}
      class="bg-base-900 border-base-600 hover:border-base-400 text-base-50 flex size-9 shrink-0 items-center justify-center rounded border font-mono text-lg hover:cursor-pointer disabled:cursor-not-allowed"
    >
      {operator_glyph(@operator)}
    </button>
    """
  end

  defp operator_glyph(operator) when operator in [:gte, "gte"], do: "≥"
  defp operator_glyph(_lte), do: "≤"

  defp operator_title(operator) when operator in [:gte, "gte"],
    do: "Unhealthy at or above the thresholds — click to flip"

  defp operator_title(_lte), do: "Unhealthy at or below the thresholds — click to flip"

  defp shown_operator(pending_operators, target, fallback) do
    Map.get(pending_operators, target) || fallback
  end

  # One section per level, warning and alert each with their own threshold
  # and measurement period, styled like the health tiles on device details:
  # a colored bottom border with a matching tint. Sections sit side by side
  # when there is room and stack on narrow screens (half-width windows,
  # tablets).
  attr(:level, :string, required: true, values: ["warning", "alert"])
  attr(:threshold, :any, default: nil)
  attr(:period_seconds, :integer, required: true)
  attr(:disabled, :boolean, default: false)

  defp level_fields(assigns) do
    ~H"""
    <div class={[
      "flex min-w-56 grow basis-56 flex-col gap-2 rounded border-b p-3",
      @level == "warning" && "border-warning health-warning",
      @level == "alert" && "border-alert health-alert"
    ]}>
      <div class={[
        "text-xs font-semibold tracking-wide uppercase",
        @level == "warning" && "text-warning",
        @level == "alert" && "text-alert"
      ]}>
        {@level}
      </div>
      <div class="flex flex-wrap items-end gap-3">
        <label class="text-base-400 flex flex-col gap-1 text-xs">
          Threshold
          <input
            type="number"
            step="any"
            required
            name={"metric[#{@level}_threshold]"}
            value={@threshold && NervesHubWeb.Components.Utils.format_number(@threshold)}
            disabled={@disabled}
            class="bg-base-900 border-base-600 focus:border-base-400 text-base-400 block w-28 rounded border px-2 py-1 focus:ring-0 sm:text-sm"
          />
        </label>
        <label class="text-base-400 flex flex-col gap-1 text-xs">
          Median over
          <div class="flex gap-2">
            <input
              type="number"
              min="1"
              step="1"
              required
              name={"metric[#{@level}_period_value]"}
              value={period_value(@period_seconds)}
              disabled={@disabled}
              class="bg-base-900 border-base-600 focus:border-base-400 text-base-400 block w-20 rounded border px-2 py-1 focus:ring-0 sm:text-sm"
            />
            <select
              name={"metric[#{@level}_period_unit]"}
              disabled={@disabled}
              class="bg-base-900 border-base-600 focus:border-base-400 text-base-400 block rounded border px-2 py-1 focus:ring-0 sm:text-sm"
            >
              {Phoenix.HTML.Form.options_for_select([{"minutes", "minutes"}, {"hours", "hours"}], period_unit(@period_seconds))}
            </select>
          </div>
        </label>
      </div>
    </div>
    """
  end

  @period_units %{"minutes" => 60, "hours" => 3600}

  # The form takes each period as a value plus a unit (so people aren't locked
  # into a preset list); the schema stores seconds. An unparseable value is
  # passed through untouched so the changeset reports it instead of a crash.
  defp normalize_periods(attrs) do
    attrs
    |> normalize_period("warning")
    |> normalize_period("alert")
  end

  defp normalize_period(attrs, level) do
    value = attrs["#{level}_period_value"]
    unit = attrs["#{level}_period_unit"]

    # A forged unit must fail validation, not be quietly reinterpreted.
    seconds =
      with {n, ""} <- Integer.parse(to_string(value)),
           {:ok, multiplier} <- Map.fetch(@period_units, unit) do
        n * multiplier
      else
        _unparseable_or_unknown_unit -> "invalid period"
      end

    attrs
    |> Map.put("#{level}_period_seconds", seconds)
    |> Map.drop(["#{level}_period_value", "#{level}_period_unit"])
  end

  # Stored seconds rendered back into the value + unit pair, preferring the
  # largest unit that divides evenly (3600 seconds shows as 1 hour). The form
  # only offers minutes and hours, so a stored sub-minute remainder (only
  # reachable via console/API today) floors to minutes — re-saving such a
  # row rewrites 90s to 60s.
  defp period_value(seconds) when is_integer(seconds) and rem(seconds, 3600) == 0, do: div(seconds, 3600)
  defp period_value(seconds) when is_integer(seconds), do: div(seconds, 60)
  defp period_value(seconds), do: seconds

  defp period_unit(seconds) when is_integer(seconds) and rem(seconds, 3600) == 0, do: "hours"
  defp period_unit(_seconds), do: "minutes"

  defp first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
