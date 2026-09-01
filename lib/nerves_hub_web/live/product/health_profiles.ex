defmodule NervesHubWeb.Live.Product.HealthProfiles do
  use NervesHubWeb, :live_view

  alias NervesHub.Devices.Metrics
  alias NervesHub.Firmwares
  alias NervesHub.Products
  alias NervesHub.Products.HealthProfiles

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

  defp metric_label(assigns, key) do
    case HealthProfiles.built_in_metrics() do
      %{^key => %{label: label}} -> label
      _ -> Map.get(assigns.custom_labels, key, key)
    end
  end

  # One bordered section per level, warning and alert each with their own
  # threshold and measurement period. Sections sit side by side when there is
  # room and stack on narrow screens (half-width windows, tablets).
  attr(:level, :string, required: true, values: ["warning", "alert"])
  attr(:threshold, :any, default: nil)
  attr(:period_minutes, :integer, required: true)
  attr(:disabled, :boolean, default: false)

  defp level_fields(assigns) do
    ~H"""
    <div class={[
      "border-base-700 flex min-w-56 grow basis-56 flex-col gap-2 rounded border border-l-2 p-3",
      @level == "warning" && "border-l-warning",
      @level == "alert" && "border-l-alert"
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
            value={@threshold}
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
              value={period_value(@period_minutes)}
              disabled={@disabled}
              class="bg-base-900 border-base-600 focus:border-base-400 text-base-400 block w-20 rounded border px-2 py-1 focus:ring-0 sm:text-sm"
            />
            <select
              name={"metric[#{@level}_period_unit]"}
              disabled={@disabled}
              class="bg-base-900 border-base-600 focus:border-base-400 text-base-400 block rounded border px-2 py-1 focus:ring-0 sm:text-sm"
            >
              {Phoenix.HTML.Form.options_for_select([{"minutes", "minutes"}, {"hours", "hours"}], period_unit(@period_minutes))}
            </select>
          </div>
        </label>
      </div>
    </div>
    """
  end

  # The form takes each period as a value plus a unit (so people aren't locked
  # into a preset list); the schema stores minutes. An unparseable value is
  # passed through untouched so the changeset reports it instead of a crash.
  defp normalize_periods(attrs) do
    attrs
    |> normalize_period("warning")
    |> normalize_period("alert")
  end

  defp normalize_period(attrs, level) do
    value = attrs["#{level}_period_value"]
    unit = attrs["#{level}_period_unit"]

    minutes =
      case Integer.parse(to_string(value)) do
        {n, ""} -> if unit == "hours", do: n * 60, else: n
        _unparseable -> value
      end

    attrs
    |> Map.put("#{level}_period_minutes", minutes)
    |> Map.drop(["#{level}_period_value", "#{level}_period_unit"])
  end

  # Stored minutes rendered back into the value + unit pair, preferring the
  # larger unit when it divides evenly (60 minutes shows as 1 hour).
  defp period_value(minutes) when is_integer(minutes) and rem(minutes, 60) == 0, do: div(minutes, 60)
  defp period_value(minutes), do: minutes

  defp period_unit(minutes) when is_integer(minutes) and rem(minutes, 60) == 0, do: "hours"
  defp period_unit(_minutes), do: "minutes"

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
