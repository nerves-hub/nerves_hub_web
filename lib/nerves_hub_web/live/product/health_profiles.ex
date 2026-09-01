defmodule NervesHubWeb.Live.Product.HealthProfiles do
  use NervesHubWeb, :live_view

  alias NervesHub.Devices.Metrics
  alias NervesHub.Firmwares
  alias NervesHub.Products
  alias NervesHub.Products.HealthProfiles

  # Offered for the measurement period selects. An existing metric with a
  # period outside this list (set via API or an older release) still renders:
  # its own value is added to the select so the form round-trips it unchanged.
  @period_options [
    {"5 minutes", 5},
    {"15 minutes", 15},
    {"30 minutes", 30},
    {"1 hour", 60},
    {"3 hours", 180},
    {"6 hours", 360},
    {"12 hours", 720},
    {"1 day", 1440},
    {"3 days", 4320},
    {"7 days", 10_080}
  ]

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

    case HealthProfiles.add_metric(profile, attrs) do
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

    case HealthProfiles.update_metric(metric, attrs) do
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

  defp period_options(selected \\ nil) do
    if selected && !Enum.any?(@period_options, fn {_label, value} -> value == selected end) do
      Enum.sort_by(@period_options ++ [{"#{selected} minutes", selected}], &elem(&1, 1))
    else
      @period_options
    end
  end

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
