defmodule NervesHubWeb.Components.DeviceHealth.MetricLabels do
  @moduledoc """
  One place to turn a health metric key into what the UI calls it, so the
  device health tab, the device details tiles, and the health profiles page
  all agree.

  A built-in health-profile metric carries its own label; otherwise a custom
  label set on the product wins; a well-known nerves_hub_health key gets its
  hand-written title; anything else is humanized from the key.
  """

  alias NervesHub.Products.HealthProfiles

  # Also the display order for the health tab's charts.
  @default_titles [
    {"load_1min", "Load Average 1 Min"},
    {"load_5min", "Load Average 5 Min"},
    {"load_15min", "Load Average 15 Min"},
    {"mem_used_mb", "Memory Usage (MB)"},
    {"mem_used_percent", "Memory Usage (%)"},
    {"disk_used_percentage", "Disk Usage (%)"},
    {"cpu_usage_percent", "CPU Usage (%)"},
    {"cpu_temp", "CPU Temperature (°C)"}
  ]

  @doc "The well-known keys with their titles, in chart display order."
  @spec default_titles() :: [{String.t(), String.t()}]
  def default_titles(), do: @default_titles

  @doc """
  The display label for `key`: a built-in's own label, else the product's
  custom label when one is set, else the derived title.
  """
  @spec label(String.t(), %{optional(String.t()) => String.t()} | nil) :: String.t()
  def label(key, custom_labels \\ %{}) do
    case HealthProfiles.built_in_metrics() do
      %{^key => %{label: label}} -> label
      _ -> Map.get(custom_labels || %{}, key) || title(key)
    end
  end

  defp title(key) do
    case List.keyfind(@default_titles, key, 0) do
      {_, title} ->
        title

      nil ->
        key
        |> String.replace("_", " ")
        |> String.capitalize()
    end
    |> String.replace(~r/mb$/, "MB")
  end
end
