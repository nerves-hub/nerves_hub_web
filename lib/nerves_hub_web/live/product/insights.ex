defmodule NervesHubWeb.Live.Product.Insights do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Firmwares
  alias NervesHub.Insights, as: InsightsQueries

  def mount(_params, _session, socket) do
    socket
    |> assign(:page_title, "#{socket.assigns.product.name} Insights")
    |> sidebar_tab(:insights)
    |> connected_devices_count()
    |> connected_device_counts_last_24_hours()
    |> not_healthy_devices_count()
    |> not_recently_seen_count()
    |> high_reconnect_count()
    |> active_firmware_count()
    |> unknown_active_firmware_count()
    |> ok()
  end

  defp connected_devices_count(%{assigns: %{product: product}} = socket) do
    assign_async(socket, :connected_devices_count, fn ->
      count = InsightsQueries.connected_count(product)
      {:ok, %{connected_devices_count: count}}
    end)
  end

  defp connected_device_counts_last_24_hours(%{assigns: %{product: product}} = socket) do
    assign_async(socket, :connected_device_counts_last_24_hours, fn ->
      count = InsightsQueries.connected_device_counts_last_24_hours(product)
      {:ok, %{connected_device_counts_last_24_hours: count}}
    end)
  end

  defp not_healthy_devices_count(%{assigns: %{product: product}} = socket) do
    assign_async(socket, :not_healthy_devices_count, fn ->
      count = InsightsQueries.not_healthy_devices_count(product)
      {:ok, %{not_healthy_devices_count: count}}
    end)
  end

  defp not_recently_seen_count(%{assigns: %{product: product}} = socket) do
    assign_async(socket, :not_recently_seen_count, fn ->
      count = InsightsQueries.not_recently_seen_count(product)
      {:ok, %{not_recently_seen_count: count}}
    end)
  end

  defp high_reconnect_count(%{assigns: %{product: product}} = socket) do
    assign_async(socket, :high_reconnect_count, fn ->
      count = InsightsQueries.high_reconnect_count(product)
      {:ok, %{high_reconnect_count: count}}
    end)
  end

  defp active_firmware_count(%{assigns: %{product: product}} = socket) do
    assign_async(socket, :active_firmware_versions_count, fn ->
      count = InsightsQueries.active_firmware_versions_count(product)
      {:ok, %{active_firmware_versions_count: count}}
    end)
  end

  defp unknown_active_firmware_count(%{assigns: %{product: product}} = socket) do
    assign_async(socket, :unknown_active_firmware_versions_count, fn ->
      versions = InsightsQueries.active_firmware_versions(product)

      uuids = Enum.map(versions, & &1.version)

      firmwares = Firmwares.get_installed_firmwares(product, uuids)

      unknown_count = length(uuids) - length(firmwares)

      {:ok, %{unknown_active_firmware_versions_count: unknown_count}}
    end)
  end
end
